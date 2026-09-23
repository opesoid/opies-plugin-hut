package net.runelite.client.plugins.microbot.opiesmoltenglass;

import net.runelite.client.plugins.microbot.Microbot;
import net.runelite.client.ui.overlay.OverlayPanel;
import net.runelite.client.ui.overlay.OverlayPosition;
import net.runelite.client.ui.overlay.components.LineComponent;
import net.runelite.client.ui.overlay.components.TitleComponent;

import javax.inject.Inject;
import java.awt.Color;
import java.awt.Dimension;
import java.awt.Graphics2D;

public class OpiesMoltenGlassOverlay extends OverlayPanel {

    private final OpiesMoltenGlassPlugin plugin;
    private final OpiesMoltenGlassConfig config;

    @Inject
    public OpiesMoltenGlassOverlay(OpiesMoltenGlassPlugin plugin, OpiesMoltenGlassConfig config) {
        super(plugin);
        this.plugin = plugin;
        this.config = config;
        setPosition(OverlayPosition.TOP_LEFT);
        setNaughty();
    }

    @Override
    public Dimension render(Graphics2D graphics) {
        if (config.hideOverlay()) {
            return null;
        }
        try {
            OpiesMoltenGlassScript script = plugin.script;
            panelComponent.setPreferredSize(new Dimension(220, 200));
            panelComponent.getChildren().add(TitleComponent.builder()
                    .text("Molten Glass")
                    .color(Color.ORANGE)
                    .build());
            panelComponent.getChildren().add(LineComponent.builder()
                    .left("Runtime")
                    .right(plugin.getTimeRunning())
                    .build());
            panelComponent.getChildren().add(LineComponent.builder()
                    .left("Status")
                    .right(Microbot.status)
                    .rightColor(Color.GREEN)
                    .build());
            panelComponent.getChildren().add(LineComponent.builder()
                    .left("State")
                    .right(script.state == null ? "-" : script.state.name())
                    .build());

            int stopAfter = config.stopAfterGlass();
            String glassCount = stopAfter > 0
                    ? script.glassMade + "/" + stopAfter
                    : String.valueOf(script.glassMade);
            panelComponent.getChildren().add(LineComponent.builder()
                    .left("Glass smelted")
                    .right(glassCount + " (" + script.glassPerHourSnapshot + "/hr)")
                    .rightColor(Color.YELLOW)
                    .build());
            panelComponent.getChildren().add(LineComponent.builder()
                    .left("Trips")
                    .right(String.valueOf(script.tripsCompleted))
                    .build());
        } catch (Exception ex) {
            Microbot.log(ex.getMessage());
        }
        return super.render(graphics);
    }
}
