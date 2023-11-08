import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/src/enums/barcode_format.dart';
import 'package:mobile_scanner/src/enums/camera_facing.dart';
import 'package:mobile_scanner/src/enums/detection_speed.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_error_code.dart';
import 'package:mobile_scanner/src/enums/torch_state.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/mobile_scanner_platform_interface.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/barcode_capture.dart';
import 'package:mobile_scanner/src/objects/mobile_scanner_state.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';

/// The controller for the [MobileScanner] widget.
class MobileScannerController extends ValueNotifier<MobileScannerState> {
  /// Construct a new [MobileScannerController] instance.
  MobileScannerController({
    this.cameraResolution,
    this.detectionSpeed = DetectionSpeed.normal,
    int detectionTimeoutMs = 250,
    this.facing = CameraFacing.back,
    this.formats = const <BarcodeFormat>[],
    this.returnImage = false,
    this.torchEnabled = false,
    this.useNewCameraSelector = false,
  })  : detectionTimeoutMs = detectionSpeed == DetectionSpeed.normal ? detectionTimeoutMs : 0,
        assert(detectionTimeoutMs >= 0, 'The detection timeout must be greater than or equal to 0.'),
        super(MobileScannerState.uninitialized(facing));

  /// The desired resolution for the camera.
  ///
  /// When this value is provided, the camera will try to match this resolution,
  /// or fallback to the closest available resolution.
  /// When this is null, Android defaults to a resolution of 640x480.
  ///
  /// Bear in mind that changing the resolution has an effect on the aspect ratio.
  ///
  /// When the camera orientation changes,
  /// the resolution will be flipped to match the new dimensions of the display.
  ///
  /// Currently only supported on Android.
  final Size? cameraResolution;

  /// The detection speed for the scanner.
  ///
  /// Defaults to [DetectionSpeed.normal].
  final DetectionSpeed detectionSpeed;

  /// The detection timeout, in milliseconds, for the scanner.
  ///
  /// This timeout is ignored if the [detectionSpeed]
  /// is not set to [DetectionSpeed.normal].
  ///
  /// By default this is set to `250` milliseconds,
  /// which prevents memory issues on older devices.
  final int detectionTimeoutMs;

  /// The facing direction for the camera.
  ///
  /// Defaults to the back-facing camera.
  final CameraFacing facing;

  /// The formats that the scanner should detect.
  ///
  /// If this is empty, all supported formats are detected.
  final List<BarcodeFormat> formats;

  /// Whether scanned barcodes should contain the image
  /// that is embedded into the barcode.
  ///
  /// If this is false, [BarcodeCapture.image] will always be null.
  ///
  /// Defaults to false, and is only supported on iOS and Android.
  final bool returnImage;

  /// Whether the flashlight should be turned on when the camera is started.
  ///
  /// Defaults to false.
  final bool torchEnabled;

  /// Use the new resolution selector.
  ///
  /// This feature is experimental and not fully tested yet.
  /// Use caution when using this flag,
  /// as the new resolution selector may produce unwanted or zoomed images.
  ///
  /// Only supported on Android.
  final bool useNewCameraSelector;

  /// The internal barcode controller, that listens for detected barcodes.
  final StreamController<BarcodeCapture> _barcodesController = StreamController.broadcast();

  /// Get the stream of scanned barcodes.
  Stream<BarcodeCapture> get barcodes => _barcodesController.stream;

  StreamSubscription<BarcodeCapture?>? _barcodesSubscription;
  StreamSubscription<TorchState>? _torchStateSubscription;
  StreamSubscription<double>? _zoomScaleSubscription;

  bool _isDisposed = false;

  void _disposeListeners() {
    _barcodesSubscription?.cancel();
    _torchStateSubscription?.cancel();
    _zoomScaleSubscription?.cancel();

    _barcodesSubscription = null;
    _torchStateSubscription = null;
    _zoomScaleSubscription = null;
  }

  void _setupListeners() {
    _barcodesSubscription = MobileScannerPlatform.instance.barcodesStream.listen((BarcodeCapture? barcode) {
      if (barcode != null) {
        _barcodesController.add(barcode);
      }
    });

    _torchStateSubscription = MobileScannerPlatform.instance.torchStateStream.listen((TorchState torchState) {
      value = value.copyWith(torchState: torchState);
    });

    _zoomScaleSubscription = MobileScannerPlatform.instance.zoomScaleStateStream.listen((double zoomScale) {
      value = value.copyWith(zoomScale: zoomScale);
    });
  }

  void _throwIfNotInitialized() {
    if (!value.isInitialized) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerUninitialized,
        errorDetails: MobileScannerErrorDetails(
          message: 'The MobileScannerController has not been initialized.',
        ),
      );
    }

    if (_isDisposed) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerDisposed,
        errorDetails: MobileScannerErrorDetails(
          message: 'The MobileScannerController was used after it has been disposed.',
        ),
      );
    }
  }

  /// Analyze an image file.
  ///
  /// The [path] points to a file on the device.
  ///
  /// This is only supported on Android and iOS.
  ///
  /// Returns the [BarcodeCapture] that was found in the image.
  Future<BarcodeCapture?> analyzeImage(String path) {
    return MobileScannerPlatform.instance.analyzeImage(path);
  }

  /// Reset the zoom scale of the camera.
  Future<void> resetZoomScale() async {
    _throwIfNotInitialized();

    // When the platform has updated the zoom scale,
    // it will send an update through the zoom scale state event stream.
    await MobileScannerPlatform.instance.resetZoomScale();
  }

  /// Set the zoom scale of the camera.
  ///
  /// The [zoomScale] must be between 0.0 and 1.0 (both inclusive).
  ///
  /// If the [zoomScale] is out of range,
  /// it is adjusted to fit within the allowed range.
  Future<void> setZoomScale(double zoomScale) async {
    _throwIfNotInitialized();

    final double clampedZoomScale = zoomScale.clamp(0.0, 1.0);

    // Update the zoom scale state to the new state.
    // When the platform has updated the zoom scale,
    // it will send an update through the zoom scale state event stream.
    await MobileScannerPlatform.instance.setZoomScale(clampedZoomScale);
  }

  /// Start scanning for barcodes.
  /// Upon calling this method, the necessary camera permission will be requested.
  ///
  /// The [cameraDirection] can be used to specify the camera direction.
  /// If this is null, this defaults to the [facing] value.
  ///
  /// Throws a [MobileScannerException] if starting the scanner failed.
  Future<void> start({CameraFacing? cameraDirection}) async {
    if (_isDisposed) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.controllerDisposed,
        errorDetails: MobileScannerErrorDetails(
          message: 'The MobileScannerController was used after it has been disposed.',
        ),
      );
    }

    final CameraFacing effectiveDirection = cameraDirection ?? facing;

    final StartOptions options = StartOptions(
      cameraDirection: effectiveDirection,
      cameraResolution: cameraResolution,
      detectionSpeed: detectionSpeed,
      detectionTimeoutMs: detectionTimeoutMs,
      formats: formats,
      returnImage: returnImage,
      torchEnabled: torchEnabled,
    );

    try {
      _setupListeners();

      final MobileScannerViewAttributes viewAttributes = await MobileScannerPlatform.instance.start(
        options,
      );

      value = value.copyWith(
        cameraDirection: effectiveDirection,
        isInitialized: true,
        size: viewAttributes.size,
      );
    } on MobileScannerException catch (error) {
      if (!_isDisposed) {
        value = value.copyWith(
          cameraDirection: facing,
          isInitialized: true,
          error: error,
        );
      }
    }
  }

  /// Stop the camera.
  ///
  /// After calling this method, the camera can be restarted using [start].
  Future<void> stop() async {
    _disposeListeners();

    _throwIfNotInitialized();

    await MobileScannerPlatform.instance.stop();

    // After the camera stopped, set the torch state to off,
    // as the torch state callback is never called when the camera is stopped.
    value = value.copyWith(torchState: TorchState.off);
  }

  /// Switch between the front and back camera.
  Future<void> switchCamera() async {
    _throwIfNotInitialized();

    await stop();

    final CameraFacing cameraDirection = value.cameraDirection;

    await start(
      cameraDirection: cameraDirection == CameraFacing.front ? CameraFacing.back : CameraFacing.front,
    );
  }

  /// Switches the flashlight on or off.
  ///
  /// Does nothing if the device has no torch.
  Future<void> toggleTorch() async {
    _throwIfNotInitialized();

    final TorchState torchState = value.torchState;

    if (torchState == TorchState.unavailable) {
      return;
    }

    final TorchState newState = torchState == TorchState.off ? TorchState.on : TorchState.off;

    // Update the torch state to the new state.
    // When the platform has updated the torch state,
    // it will send an update through the torch state event stream.
    await MobileScannerPlatform.instance.setTorchState(newState);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    await MobileScannerPlatform.instance.dispose();
    unawaited(_barcodesController.close());

    _isDisposed = true;
    super.dispose();
  }
}
