package kalsubai.wrkfarm

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val configChannel = "grainright.wrkfarm/config"
    private val notificationChannel = "grainright.wrkfarm/notifications"
    private val notificationChannelId = "farmer_alerts"
    private val notificationGroup = "grainright_farmer_alerts"
    private val notificationPermissionRequestCode = 7401
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationPayload: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.enableEdgeToEdge(window)
        captureNotificationPayload(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureNotificationPayload(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            configChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "mapTilerApiKey" -> result.success(BuildConfig.MAPTILER_API_KEY)
                "offlineTileUrlTemplate" -> result.success(BuildConfig.OFFLINE_TILE_URL_TEMPLATE)
                "offlineTileSourceLabel" -> result.success(BuildConfig.OFFLINE_TILE_SOURCE_LABEL)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    createNotificationChannel()
                    result.success(true)
                }
                "requestPermission" -> requestNotificationPermission(result)
                "showNotification" -> result.success(showNotification(call.arguments))
                "consumeNotificationPayload" -> result.success(consumeNotificationPayload())
                else -> result.notImplemented()
            }
        }
    }

    private fun captureNotificationPayload(intent: Intent?) {
        val payload = intent?.getStringExtra("notification_payload").orEmpty().trim()
        if (payload.isNotEmpty()) {
            pendingNotificationPayload = payload
        }
    }

    private fun consumeNotificationPayload(): String {
        val payload = pendingNotificationPayload.orEmpty()
        pendingNotificationPayload = null
        return payload
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }

        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun showNotification(arguments: Any?): Boolean {
        createNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val args = arguments as? Map<*, *> ?: return false
        val title = args["title"] as? String ?: return false
        val message = args["message"] as? String ?: return false
        if (title.isBlank() || message.isBlank()) return false
        val farmName = (args["farmName"] as? String).orEmpty().trim()
        val type = (args["type"] as? String).orEmpty().trim()
        val subText = when {
            farmName.isNotBlank() -> farmName
            type.contains("disease", ignoreCase = true) -> "Disease alert"
            type.contains("status", ignoreCase = true) -> "Farm status"
            else -> "Kalsubai Farms"
        }

        val id = when (val rawId = args["id"]) {
            is Number -> rawId.toInt()
            is String -> rawId.toIntOrNull() ?: rawId.hashCode()
            else -> System.currentTimeMillis().toInt()
        }
        val payload = args["payload"] as? String ?: ""
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("notification_payload", payload)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pendingIntent = PendingIntent.getActivity(this, id, intent, flags)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setSmallIcon(R.drawable.ic_stat_notification)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.kalsubai_farms))
            .setContentTitle(title)
            .setContentText(message)
            .setSubText(subText)
            .setTicker(title)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setStyle(
                Notification.BigTextStyle()
                    .setBigContentTitle(title)
                    .bigText(message)
                    .setSummaryText(subText)
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setColor(Color.rgb(11, 93, 42))
            .setGroup(notificationGroup)
            .setDefaults(Notification.DEFAULT_ALL)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, builder.build())
        return true
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            notificationChannelId,
            "Kalsubai Farms alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Important farm status, disease, weather, and crop alerts from Kalsubai Farms"
            lightColor = Color.rgb(11, 93, 42)
            enableLights(true)
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }
}
