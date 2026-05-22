import QtQuick 2.0
import QtQuick.Controls 2.5 as QQC2
import QtQuick.Layouts 1.1 as QQL
import org.kde.kirigami 2.4 as Kirigami
import org.kde.kcmutils as KCMUtils

KCMUtils.SimpleKCM {
    id: root

    property alias cfg_enableOpenLinkHubIntegration: enableOpenLinkHubIntegration.checked
    property alias cfg_openLinkHubApiPort: openLinkHubApiPort.value

    property alias cfg_enableOpenRazerIntegration: enableOpenRazerIntegration.checked
    property alias cfg_openRazerPollingTime: openRazerPollingTime.value

    property alias cfg_enableKDEConnectIntegration: enableKDEConnectIntegration.checked
    property alias cfg_kdeConnectPollingTime: kdeConnectPollingTime.value

    property alias cfg_enableSteamControllerIntegration: enableSteamControllerIntegration.checked
    property alias cfg_steamControllerPollingTime: steamControllerPollingTime.value

    Kirigami.FormLayout {
        id: page

        // anchors.left: parent.left
        // anchors.right: parent.right

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("OpenLinkHub Integration")
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Enable")

            QQC2.CheckBox {
                id: enableOpenLinkHubIntegration
        }
        }

        QQC2.SpinBox {
            id: openLinkHubApiPort
            Kirigami.FormData.label: i18n("Port: ")
            to: 65535
            enabled: enableOpenLinkHubIntegration.checked
        }
        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("OpenRazer Integration")
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Enable")

            QQC2.CheckBox {
                id: enableOpenRazerIntegration
            }
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Polling interval")

            QQC2.SpinBox {
                id: openRazerPollingTime
                enabled: enableOpenRazerIntegration.checked
                from: 1
                to: 3600
            }

            QQC2.Label {
                text: i18n("s")
                opacity: enableOpenRazerIntegration.checked ? 0.7 : 0.5
            }
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("KDE Connect Integration")
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Enable")

            QQC2.CheckBox {
                id: enableKDEConnectIntegration
            }
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Polling interval")

            QQC2.SpinBox {
                id: kdeConnectPollingTime
                enabled: enableKDEConnectIntegration.checked
                from: 5
                to: 3600
            }

            QQC2.Label {
                text: i18n("s")
                opacity: enableKDEConnectIntegration.checked ? 0.7 : 0.5
            }
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Steam Controller 2 Integration")
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Enable")

            QQC2.CheckBox {
                id: enableSteamControllerIntegration
            }
        }

        QQL.RowLayout {
            Kirigami.FormData.label: i18n("Polling interval")

            QQC2.SpinBox {
                id: steamControllerPollingTime
                enabled: enableSteamControllerIntegration.checked
                from: 5
                to: 3600
            }

            QQC2.Label {
                text: i18n("s")
                opacity: enableSteamControllerIntegration.checked ? 0.7 : 0.5
            }
        }
    }
}
