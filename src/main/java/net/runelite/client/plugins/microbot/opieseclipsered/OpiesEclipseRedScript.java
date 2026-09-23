package net.runelite.client.plugins.microbot.opieseclipsered;

import lombok.extern.slf4j.Slf4j;
import net.runelite.api.coords.WorldPoint;
import net.runelite.client.plugins.microbot.Microbot;
import net.runelite.client.plugins.microbot.Script;
import net.runelite.client.plugins.microbot.util.antiban.Rs2Antiban;
import net.runelite.client.plugins.microbot.util.antiban.enums.Activity;
import net.runelite.client.plugins.microbot.util.antiban.enums.ActivityIntensity;
import net.runelite.client.plugins.microbot.util.bank.Rs2Bank;
import net.runelite.client.plugins.microbot.util.bank.enums.BankLocation;
import net.runelite.client.plugins.microbot.util.grounditem.Rs2GroundItem;
import net.runelite.client.plugins.microbot.util.inventory.Rs2Inventory;
import net.runelite.client.plugins.microbot.util.math.Rs2Random;
import net.runelite.client.plugins.microbot.util.models.RS2Item;
import net.runelite.client.plugins.microbot.util.player.Rs2Player;
import net.runelite.client.plugins.microbot.util.walker.Rs2Walker;
import net.runelite.client.plugins.microbot.util.world.Rs2WorldUtil;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.TimeUnit;

@Slf4j
public class OpiesEclipseRedScript extends Script {

    static final int ECLIPSE_RED_ID = 29415;
    static final int WINE_VALUE_GP = 700;
    static final WorldPoint WINE_TILE = new WorldPoint(1555, 3035, 2);
    private static final int MAX_WORLD_REROLLS = 30;

    public volatile State state = State.TRAVEL_TO_SPAWN;
    public volatile int winesCollected;
    public volatile int hopCount;
    public volatile int currentWorld;
    /** Stable wines/hr snapshot recalculated once per bank trip (not every render tick). */
    public volatile int winesPerHourSnapshot;

    private static final long TRAVEL_TIMEOUT_MS = 120_000;
    private long travelStartMs = 0;

    private final Map<Integer, Long> worldCooldowns = new HashMap<>();
    private boolean membershipChecked;

    public boolean run(OpiesEclipseRedConfig config) {
        shutdown();
        state = State.TRAVEL_TO_SPAWN;
        winesCollected = 0;
        hopCount = 0;
        currentWorld = 0;
        travelStartMs = 0;
        winesPerHourSnapshot = 0;
        membershipChecked = false;
        worldCooldowns.clear();
        Microbot.status = "Starting Eclipse Red";

        // Wire antiban: Hunter-style setup (fast-paced movement/collection),
        // activity set to GENERAL_COLLECTING since we are looting a spawn repeatedly.
        Rs2Antiban.resetAntibanSettings();
        Rs2Antiban.antibanSetupTemplates.applyHunterSetup();
        Rs2Antiban.setActivity(Activity.GENERAL_COLLECTING);
        Rs2Antiban.setActivityIntensity(ActivityIntensity.HIGH);

        mainScheduledFuture = scheduledExecutorService.scheduleWithFixedDelay(() -> {
            try {
                if (!Microbot.isLoggedIn()) {
                    return;
                }
                if (!super.run()) {
                    return;
                }
                if (!ensureMember()) {
                    return;
                }

                currentWorld = Microbot.getClient().getWorld();
                int wineCount = Rs2Inventory.count(ECLIPSE_RED_ID);

                if (reachedStopLimit(config)) {
                    if (wineCount > 0) {
                        state = State.BANK;
                    } else {
                        stopAtGoal(config);
                        return;
                    }
                } else if (wineCount >= config.wineThreshold() || (Rs2Inventory.isFull() && wineCount > 0)) {
                    state = State.BANK;
                }

                switch (state) {
                    case TRAVEL_TO_SPAWN:
                        travelToSpawn();
                        break;
                    case LOOT:
                        loot(config);
                        break;
                    case HOP:
                        hop(config);
                        break;
                    case BANK:
                        bank(config);
                        break;
                    default:
                        break;
                }
            } catch (Exception ex) {
                if (ex instanceof InterruptedException) {
                    Thread.currentThread().interrupt();
                    return;
                }
                Microbot.logStackTrace(getClass().getSimpleName(), ex);
            }
        }, 0, 200, TimeUnit.MILLISECONDS);

        return true;
    }

    private boolean ensureMember() {
        if (membershipChecked) {
            return true;
        }
        if (!Rs2Player.isMember()) {
            Microbot.status = "Membership required. Stopping.";
            log.warn("Account is not a member. Hunter Guild is members-only.");
            shutdown();
            return false;
        }
        if (!Rs2Player.isInMemberWorld()) {
            Microbot.status = "Must be on a members world. Stopping.";
            log.warn("Player is not in a members world.");
            shutdown();
            return false;
        }
        membershipChecked = true;
        return true;
    }

    private void travelToSpawn() {
        if (travelStartMs == 0) {
            travelStartMs = System.currentTimeMillis();
        }
        if (System.currentTimeMillis() - travelStartMs > TRAVEL_TIMEOUT_MS) {
            Microbot.status = "Could not reach spawn after 2 minutes - stopping";
            log.error("travelToSpawn timed out after {}ms; shutting down", TRAVEL_TIMEOUT_MS);
            shutdown();
            return;
        }
        Microbot.status = "Walking to Eclipse red spawn";
        if (isOnWineTile()) {
            travelStartMs = 0;
            state = State.LOOT;
            return;
        }
        Rs2Walker.walkTo(WINE_TILE, 0);
        if (isOnWineTile()) {
            travelStartMs = 0;
            state = State.LOOT;
        }
    }

    private void loot(OpiesEclipseRedConfig config) {
        if (!isOnWineTile()) {
            travelStartMs = 0;
            state = State.TRAVEL_TO_SPAWN;
            return;
        }

        int before = Rs2Inventory.count(ECLIPSE_RED_ID);
        if (before >= config.wineThreshold() || Rs2Inventory.isFull()) {
            state = State.BANK;
            return;
        }

        Microbot.status = "Waiting for Eclipse red";
        boolean appeared = sleepUntil(this::wineOnTile, config.maxWaitForWineMs());
        if (!appeared) {
            state = State.HOP;
            return;
        }

        Microbot.status = "Looting Eclipse red";
        Rs2GroundItem.loot(ECLIPSE_RED_ID, 2);
        boolean picked = sleepUntil(() -> Rs2Inventory.count(ECLIPSE_RED_ID) > before, 4000);
        if (picked) {
            winesCollected++;
            // Human-like hesitation after picking up the item, then glance around.
            Rs2Antiban.actionCooldown();
            Rs2Antiban.moveMouseRandomly();
            int after = Rs2Inventory.count(ECLIPSE_RED_ID);
            if (reachedStopLimit(config)) {
                if (after > 0) {
                    state = State.BANK;
                } else {
                    stopAtGoal(config);
                }
            } else if (after >= config.wineThreshold() || Rs2Inventory.isFull()) {
                state = State.BANK;
            } else {
                state = State.HOP;
            }
            return;
        }

        if (!wineOnTile()) {
            state = State.HOP;
        }
    }

    private void hop(OpiesEclipseRedConfig config) {
        if (Rs2Bank.isOpen()) {
            Rs2Bank.closeBank();
            sleepUntil(() -> !Rs2Bank.isOpen(), 3000);
        }
        if (Rs2Player.isInCombat()) {
            Microbot.status = "Waiting to leave combat before hop";
            sleepUntil(() -> !Rs2Player.isInCombat(), 10000);
            if (Rs2Player.isInCombat()) {
                return;
            }
        }

        int current = Microbot.getClient().getWorld();
        int target = pickSafeWorld(config, current);
        if (target <= 0) {
            Microbot.status = "No safe members world available";
            return;
        }

        Microbot.status = "Hopping to world " + target;
        boolean hopped = Microbot.hopToWorld(target);
        if (!hopped) {
            // The world hopper needs a warm-up on the first call of a session — the
            // interface hasn't been opened before so isHopping() doesn't fire in time
            // and hopToWorld returns false after ~5s. Retry once; the interface is now
            // initialised and the second attempt succeeds immediately.
            sleep(400);
            hopped = Microbot.hopToWorld(target);
            if (!hopped) {
                Microbot.status = "Hop failed, retrying";
                return;
            }
        }

        // Record cooldown only after a confirmed successful hop.
        worldCooldowns.put(current, System.currentTimeMillis());
        hopCount++;
        currentWorld = target;

        // Short settle: allow ground items to register (~1-2 game ticks) after world change.
        // This replaced the old 800-1200ms stabilisation sleep + 1000-2500ms user delay.
        sleep(Rs2Random.betweenInclusive(300, 500));

        // Antiban: natural variable pause while the player "looks around" the new world.
        // Resolves to zero if the antiban panel has play style disabled.
        Rs2Antiban.actionCooldown();
        Rs2Antiban.takeMicroBreakByChance();

        // Player always lands at the fairy ring (plane 0), never on the wine tile (plane 2).
        travelStartMs = 0;
        state = State.TRAVEL_TO_SPAWN;
    }

    private void bank(OpiesEclipseRedConfig config) {
        Microbot.status = "Banking Eclipse red";
        // Handle a bank PIN dialog that may appear before the bank is fully open.
        enterPinIfNeeded(config);
        if (!Rs2Bank.walkToBankAndUseBank(BankLocation.HUNTERS_GUILD)) {
            return;
        }
        // Handle PIN again in case it appeared during the walk/open sequence.
        enterPinIfNeeded(config);
        if (!Rs2Bank.isOpen()) {
            return;
        }
        Rs2Bank.depositAll(ECLIPSE_RED_ID);
        sleepUntil(() -> Rs2Inventory.count(ECLIPSE_RED_ID) == 0, 4000);
        Rs2Bank.closeBank();
        sleepUntil(() -> !Rs2Bank.isOpen(), 3000);

        // Recalculate wines/hr once per bank trip so the overlay shows a stable,
        // meaningful rate rather than updating every render tick.
        updateWinesPerHour();

        // Player naturally takes a short break after banking (looking at inventory, etc.).
        Rs2Antiban.takeMicroBreakByChance();

        if (reachedStopLimit(config)) {
            stopAtGoal(config);
            return;
        }
        if (config.afterBanking() == OpiesEclipseRedConfig.AfterBanking.STOP) {
            Microbot.status = "Banked. Stopping as configured.";
            shutdown();
            return;
        }
        travelStartMs = 0;
        state = State.TRAVEL_TO_SPAWN;
    }

    /** Set by the Plugin on startUp so the script can compute per-hour stats at banking time. */
    public volatile long scriptStartEpochMs = 0;

    private void updateWinesPerHour() {
        if (scriptStartEpochMs <= 0 || winesCollected <= 0) return;
        long runtimeMs = System.currentTimeMillis() - scriptStartEpochMs;
        double hours = runtimeMs / 3_600_000.0;
        if (hours > 0) {
            winesPerHourSnapshot = (int) (winesCollected / hours);
        }
    }

    private boolean reachedStopLimit(OpiesEclipseRedConfig config) {
        int limit = targetWines(config);
        return limit > 0 && winesCollected >= limit;
    }

    private void stopAtGoal(OpiesEclipseRedConfig config) {
        int gp = winesCollected * WINE_VALUE_GP;
        if (config.stopGoal() == OpiesEclipseRedConfig.StopGoal.GP) {
            Microbot.status = "Reached " + formatGp(gp) + " / " + formatGp(targetGp(config)) + ". Stopping.";
        } else {
            Microbot.status = "Collected " + winesCollected + "/" + targetWines(config) + " wines. Stopping.";
        }
        shutdown();
    }

    static int targetWines(OpiesEclipseRedConfig config) {
        if (config.stopGoal() == OpiesEclipseRedConfig.StopGoal.GP) {
            int k = config.stopAfterGpK();
            if (k <= 0) {
                return 0;
            }
            return (int) Math.ceil((k * 1000L) / (double) WINE_VALUE_GP);
        }
        return config.stopAfterWines();
    }

    static long targetGp(OpiesEclipseRedConfig config) {
        return Math.max(0, config.stopAfterGpK()) * 1000L;
    }

    static String formatGp(long gp) {
        if (gp >= 1_000_000) {
            double mil = gp / 1_000_000.0;
            if (mil == Math.floor(mil)) {
                return ((long) mil) + "m";
            }
            return String.format("%.1fm", mil);
        }
        if (gp >= 1_000) {
            return (gp / 1_000) + "k";
        }
        return String.valueOf(gp);
    }

    private int pickSafeWorld(OpiesEclipseRedConfig config, int current) {
        long now = System.currentTimeMillis();
        long cooldownMs = config.worldCooldownSeconds() * 1000L;
        for (int i = 0; i < MAX_WORLD_REROLLS; i++) {
            int world = Rs2WorldUtil.getRandomAccessibleWorld(
                    config.avoidEmptyWorlds(),
                    config.avoidOvercrowdedWorlds(),
                    true);
            if (world <= 0 || world == current) {
                continue;
            }
            Long lastVisit = worldCooldowns.get(world);
            if (lastVisit != null && now - lastVisit < cooldownMs) {
                continue;
            }
            return world;
        }
        // Last-resort fallback: still exclude the current world so we never "hop" to ourselves.
        int fallback = Rs2WorldUtil.getRandomAccessibleWorld(
                config.avoidEmptyWorlds(),
                config.avoidOvercrowdedWorlds(),
                true);
        return fallback == current ? -1 : fallback;
    }

    private void enterPinIfNeeded(OpiesEclipseRedConfig config) {
        if (!Rs2Bank.isBankPinWidgetVisible()) {
            return;
        }
        String pin = config.bankPin();
        if (pin == null || pin.isBlank()) {
            return;
        }
        if (pin.length() != 4 || !pin.matches("\\d{4}")) {
            log.warn("Bank PIN '{}' is not a valid 4-digit number; skipping PIN entry.", "****");
            return;
        }
        Microbot.status = "Entering bank PIN";
        Rs2Bank.handleBankPin(pin);
    }

    private boolean isOnWineTile() {
        WorldPoint loc = Rs2Player.getWorldLocation();
        return loc != null && loc.equals(WINE_TILE);
    }

    private boolean wineOnTile() {
        RS2Item[] items = Rs2GroundItem.getAllAt(WINE_TILE.getX(), WINE_TILE.getY());
        if (items == null) {
            return false;
        }
        for (RS2Item item : items) {
            if (item != null && item.getItem() != null && item.getItem().getId() == ECLIPSE_RED_ID) {
                return true;
            }
        }
        return false;
    }

    @Override
    public void shutdown() {
        worldCooldowns.clear();
        membershipChecked = false;
        Rs2Antiban.resetAntibanSettings();
        super.shutdown();
    }

    public enum State {
        TRAVEL_TO_SPAWN,
        LOOT,
        HOP,
        BANK
    }
}
