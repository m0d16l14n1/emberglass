/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Emberglass panel widget: shows what the emberglass sampler writes to /run/emberglass. panel.txt (one short line)
 * goes in the panel, detail.txt in the popup and the tooltip. Reading those files costs nothing on the hardware
 * side: the sampler is the only reader of the sensors.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property string panelText: "…"
    property string detailText: "Waiting for /run/emberglass (emberglass.service)"
    readonly property string command: "cat /run/emberglass/panel.txt /run/emberglass/detail.txt"

    preferredRepresentation: compactRepresentation
    toolTipMainText: "Emberglass"
    toolTipSubText: detailText

    P5Support.DataSource {
        id: reader
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            const out = (data["stdout"] || "").trim();
            if (out.length > 0) {
                const lines = out.split("\n");
                root.panelText = lines[0];
                root.detailText = lines.slice(1).join("\n");
            } else {
                root.panelText = "–";
                root.detailText = "No data: is emberglass.service running?";
            }
            disconnectSource(source);
        }
    }

    Timer {
        interval: root.expanded ? 1000 : 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: reader.connectSource(root.command)
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded

        PlasmaComponents.Label {
            id: label
            anchors.centerIn: parent
            text: root.panelText
            font.features: { "tnum": 1 }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: details.implicitHeight + Kirigami.Units.largeSpacing * 2

        PlasmaComponents.Label {
            id: details
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.largeSpacing
            text: root.detailText
            textFormat: Text.PlainText
            font.family: "monospace"
        }
    }
}
