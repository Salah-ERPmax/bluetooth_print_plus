import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

import 'bluetooth_print_model.dart';

class BluetoothPrintPlus {
  BluetoothPrintPlus._() {
    _channel.setMethodCallHandler((MethodCall call) async {
      _methodStreamController.add(call);
    });
  }

  static final BluetoothPrintPlus _instance = BluetoothPrintPlus._();

  static BluetoothPrintPlus get instance => _instance;

  static const int connected = 1;
  static const int disconnected = 0;

  static const MethodChannel _channel =
      MethodChannel("bluetooth_print_plus/methods");
  static const EventChannel _stateChannel =
      EventChannel('bluetooth_print_plus/state');

  Stream<MethodCall> get _methodStream => _methodStreamController.stream;
  final StreamController<MethodCall> _methodStreamController =
      StreamController.broadcast();

  Future<bool> get isAvailable async =>
      await _channel.invokeMethod('isAvailable').then<bool>((d) => d);

  Future<bool> get isOn async =>
      await _channel.invokeMethod('isOn').then<bool>((d) => d);

  Future<bool?> get isConnected async =>
      await _channel.invokeMethod('isConnected');

  final BehaviorSubject<bool> _isScanning = BehaviorSubject.seeded(false);

  Stream<bool> get isScanning => _isScanning.stream;

  final BehaviorSubject<List<BluetoothDevice>> _scanResults =
      BehaviorSubject.seeded([]);

  Stream<List<BluetoothDevice>> get scanResults => _scanResults.stream;

  final PublishSubject _stopScanPill = PublishSubject();

  /// Gets the current state of the Bluetooth module
  Stream<int> get state async* {
    yield await _channel.invokeMethod('state').then((s) => s);

    yield* _stateChannel.receiveBroadcastStream().map((s) => s);
  }

  /// Starts a scan for Bluetooth Low Energy devices
  /// Timeout closes the stream after a specified [Duration]
  Stream<BluetoothDevice> scan({
    Duration? timeout,
  }) async* {
    // Emit to isScanning
    _isScanning.add(true);
    final killStreams = <Stream>[];
    killStreams.add(_stopScanPill);
    if (timeout != null) {
      killStreams.add(Rx.timer(null, timeout));
    }
    // Clear scan results list
    _scanResults.add(<BluetoothDevice>[]);

    try {
      await _channel.invokeMethod('startScan');
    } catch (e) {
      print('Error starting scan.');
      _stopScanPill.add(null);
      _isScanning.add(false);
      throw e;
    }

    yield* BluetoothPrintPlus.instance._methodStream
        .where((m) => m.method == "ScanResult")
        .map((m) => m.arguments)
        .takeUntil(Rx.merge(killStreams))
        .doOnDone(stopScan)
        .map((map) {
      final device = BluetoothDevice.fromJson(Map<String, dynamic>.from(map));
      final List<BluetoothDevice> list = _scanResults.value;
      int newIndex = -1;
      list.asMap().forEach((index, e) {
        if (e.address == device.address) {
          newIndex = index;
        }
      });

      if (newIndex != -1) {
        list[newIndex] = device;
      } else {
        list.add(device);
      }
      _scanResults.add(list);
      return device;
    });
  }

  Future startScan({
    Duration? timeout,
  }) async {
    await scan(timeout: timeout).drain();
    return _scanResults.value;
  }

  /// Stops a scan for Bluetooth Low Energy devices
  Future stopScan() async {
    await _channel.invokeMethod('stopScan');
    _stopScanPill.add(null);
    _isScanning.add(false);
  }

  Future<dynamic> connect(BluetoothDevice device) =>
      _channel.invokeMethod('connect', device.toJson());

  Future<dynamic> disconnect() => _channel.invokeMethod('disconnect');

  Future<dynamic> destroy() => _channel.invokeMethod('destroy');

  Future<dynamic> write(Uint8List? data) async {
    await _channel.invokeMethod('write', {"data": data});
  }
}
