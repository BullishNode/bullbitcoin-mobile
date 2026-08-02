package com.bullbitcoin.mobile

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity(), EventChannel.StreamHandler, SensorEventListener {
    private var motionChannel: EventChannel? = null
    private var sensorManager: SensorManager? = null
    private var eventSink: EventChannel.EventSink? = null
    private var sequence = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        motionChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ENTROPY_MOTION_CHANNEL,
        ).also { it.setStreamHandler(this) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopMotionSensors()
        motionChannel?.setStreamHandler(null)
        motionChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopMotionSensors()
        eventSink = events
        sequence = 0

        val manager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        sensorManager = manager
        val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val gyroscope = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        var registered = false
        if (accelerometer != null) {
            registered = manager.registerListener(this, accelerometer, SAMPLE_PERIOD_MICROS) || registered
        }
        if (gyroscope != null) {
            registered = manager.registerListener(this, gyroscope, SAMPLE_PERIOD_MICROS) || registered
        }
        if (!registered) {
            stopMotionSensors()
            events.error("motion_unavailable", "No accelerometer or gyroscope is available", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stopMotionSensors()
    }

    override fun onSensorChanged(event: SensorEvent) {
        val source = when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> SOURCE_ACCELEROMETER
            Sensor.TYPE_GYROSCOPE -> SOURCE_GYROSCOPE
            else -> return
        }
        if (event.values.size < 3) return

        eventSink?.success(
            listOf(
                source,
                sequence++,
                event.timestamp,
                SystemClock.elapsedRealtimeNanos(),
                event.values[0].toDouble(),
                event.values[1].toDouble(),
                event.values[2].toDouble(),
                event.accuracy,
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun stopMotionSensors() {
        sensorManager?.unregisterListener(this)
        sensorManager = null
        eventSink = null
    }

    private companion object {
        const val ENTROPY_MOTION_CHANNEL = "com.bullbitcoin.mobile/entropy_motion"
        const val SAMPLE_PERIOD_MICROS = 10_000
        const val SOURCE_ACCELEROMETER = 0
        const val SOURCE_GYROSCOPE = 1
    }
}
