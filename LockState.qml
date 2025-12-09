pragma Singleton
import QtQuick

QtObject {
    property bool locked: false
    onLockedChanged: {
        console.log("LockState locked changed to: ", locked);
    }
}