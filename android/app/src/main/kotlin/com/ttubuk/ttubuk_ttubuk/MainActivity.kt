package com.ttubuk.ttubuk_ttubuk

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.ttubuk.ttubuk_ttubuk/steps"
    private var sensorManager: SensorManager? = null
    private var stepCounterSensor: Sensor? = null
    private var rawStepCount = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 폰 내부의 센서 매니저 가동
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        stepCounterSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        
        // 백그라운드 및 앱 가동 시 센서 리스너 등록
        stepCounterSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getRawSensorSteps" -> {
                    result.success(rawStepCount)
                }
                "isSensorAvailable" -> {
                    val isAvailable = stepCounterSensor != null
                    result.success(isAvailable)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event != null && event.sensor.type == Sensor.TYPE_STEP_COUNTER) {
            // 부팅 이후 총 원시 누적 걸음수 동적 실시간 캐싱
            rawStepCount = event.values[0].toInt()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // 단말 정확도 사양 변경 리스너 (사용 안 함)
    }

    override fun onResume() {
        super.onResume()
        stepCounterSensor?.let {
            sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager?.unregisterListener(this)
    }
}
