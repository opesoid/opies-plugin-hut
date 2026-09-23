package net.runelite.client.plugins.microbot.opiesmoltenglass;

import com.google.inject.Provides;
import lombok.extern.slf4j.Slf4j;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import net.runelite.client.plugins.microbot.PluginConstants;
import net.runelite.client.plugins.microbot.util.misc.TimeUtils;
import net.runelite.client.ui.overlay.OverlayManager;

import javax.inject.Inject;
import java.time.Instant;

@PluginDescriptor(
        name = PluginConstants.OPIE + "Molten Glass",
        description = "Withdraws sand and soda ash at Edgeville, smelts molten glass at the nearby furnace, and banks",
        tags = {"molten glass", "crafting", "edgeville", "furnace", "opie"},
        authors = {"Opie"},
        version = OpiesMoltenGlassPlugin.version,
        minClientVersion = "1.9.6",
        enabledByDefault = PluginConstants.DEFAULT_ENABLED,
        isExternal = PluginConstants.IS_EXTERNAL
)
@Slf4j
public class OpiesMoltenGlassPlugin extends Plugin {
    static final String CONFIG = "opiesmoltenglass";
    public static final String version = "1.0.2";

    public Instant scriptStartTime;

    @Inject
    OpiesMoltenGlassScript script;
    @Inject
    private OverlayManager overlayManager;
    @Inject
    private OpiesMoltenGlassConfig config;
    @Inject
    private OpiesMoltenGlassOverlay overlay;

    @Override
    protected void startUp() {
        scriptStartTime = Instant.now();
        script.scriptStartEpochMs = scriptStartTime.toEpochMilli();
        if (overlayManager != null) {
            overlayManager.add(overlay);
        }
        script.run(config);
    }

    @Override
    protected void shutDown() {
        scriptStartTime = null;
        if (overlayManager != null) {
            overlayManager.remove(overlay);
        }
        script.shutdown();
    }

    @Provides
    OpiesMoltenGlassConfig provideConfig(ConfigManager configManager) {
        return configManager.getConfig(OpiesMoltenGlassConfig.class);
    }

    String getTimeRunning() {
        return scriptStartTime != null
                ? TimeUtils.getFormattedDurationBetween(scriptStartTime, Instant.now())
                : "";
    }
}
