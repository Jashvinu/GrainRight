package grainright.wrkfarm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val configChannel = "grainright.wrkfarm/config"

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
    }
}
