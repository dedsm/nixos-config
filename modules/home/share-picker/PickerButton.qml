import QtQuick

Rectangle {
    id: button
    property string text
    property string detail
    property bool hot: false
    property bool quiet: false
    property real maxWidth: 480
    signal clicked

    width: Math.min(Math.max(title.implicitWidth, sub.implicitWidth) + 48, maxWidth)
    height: sub.text ? 64 : 44
    radius: 12
    color: quiet ? (area.containsMouse ? "#55ffffff" : "#33ffffff")
                 : (hot || area.containsMouse ? "#4f8cff" : "#ee1c1c20")

    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 2
        Text {
            id: title
            width: parent.width
            text: button.text
            color: "white"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
        Text {
            id: sub
            width: parent.width
            visible: text.length > 0
            text: button.detail
            color: "#ccffffff"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
