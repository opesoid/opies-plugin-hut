package net.runelite.client.plugins.microbot.opieseclipsered;

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
        name = PluginConstants.OPIE + "Eclipse Red",
        description = "Hops safe members worlds collecting the Hunter Guild Eclipse red spawn",
        tags = {"eclipse red", "wine", "ironman", "money", "opie"},
        authors = {"Opie"},
        version = OpiesEclipseRedPlugin.version,
        minClientVersion = "1.9.6",
        enabledByDefault = PluginConstants.DEFAULT_ENABLED,
        isExternal = PluginConstants.IS_EXTERNAL
)
@Slf4j
public class OpiesEclipseRedPlugin extends Plugin {
    public static final String version = "1.2.3";
    static final String CONFIG = "opieseclipsered";

    public Instant scriptStartTime;

    @Inject
    OpiesEclipseRedScript script;
    @Inject
    private OverlayManager overlayManager;
    @Inject
    private OpiesEclipseRedConfig config;
    @Inject
    private OpiesEclipseRedOverlay overlay;

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
    OpiesEclipseRedConfig provideConfig(ConfigManager configManager) {
        return configManager.getConfig(OpiesEclipseRedConfig.class);
    }

    String getTimeRunning() {
        return scriptStartTime != null
                ? TimeUtils.getFormattedDurationBetween(scriptStartTime, Instant.now())
                : "";
    }
}
