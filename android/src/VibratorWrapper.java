package center.dx.wingout;

import android.content.Context;
import android.os.Build;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.os.VibrationEffect;
import java.util.logging.Logger;

public class VibratorWrapper {
    private static final Logger logger = Logger.getLogger(VibratorWrapper.class.getName());
    public static void vibrate(Context context, long duration, int effect) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            logger.warning("SDK version is too low");
            return;
        }
        VibratorManager vm = (VibratorManager) context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
        if (vm == null) {
            logger.warning("unable to find a VibratorManager");
            return;
        }
        Vibrator vibrator = vm.getDefaultVibrator();
        if (vibrator == null) {
            logger.warning("unable to get the default vibrator");
            return;
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            logger.warning("SDK version is too low");
            return;
        }
        if (!vibrator.hasVibrator()) {
            logger.warning("the device has no vibrator");
            return;
        }
        vibrator.vibrate(VibrationEffect.createOneShot(duration, effect));
        logger.info("vibrate()");
    }
}