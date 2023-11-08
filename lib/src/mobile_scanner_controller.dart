import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/src/enums/barcode_format.dart';
import 'package:mobile_scanner/src/enums/camera_facing.dart';
import 'package:mobile_scanner/src/enums/detection_speed.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_error_code.dart';
import 'package:mobile_scanner/src/enums/mobile_scanner_state.dart';
import 'package:mobile_scanner/src/enums/torch_state.dart';
import 'package:mobile_scanner/src/mobile_scanner_exception.dart';
import 'package:mobile_scanner/src/mobile_scanner_platform_interface.dart';
import 'package:mobile_scanner/src/objects/barcode_capture.dart';

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
    await MobileScannerPlatform.instance.resetZoomScale();
  }

  /// Set the zoom scale of the camera.
  ///
  /// The [zoomScale] must be between 0.0 and 1.0 (both inclusive).
  Future<void> setZoomScale(double zoomScale) async {
    if (zoomScale < 0 || zoomScale > 1) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
        errorDetails: MobileScannerErrorDetails(
          message: 'The zoomScale must be between 0.0 and 1.0',
        ),
      );
    }

    await MobileScannerPlatform.instance.setZoomScale(zoomScale);
  }

  /// Stop the camera.
  ///
  /// After calling this method, the camera can be restarted using [start].
  Future<void> stop() async {
    await MobileScannerPlatform.instance.stop();

    // After the camera stopped, set the torch state to off,
    // as the torch state callback is never called when the camera is stopped.
    torchState.value = TorchState.off;
  }

  /// Switch between the front and back camera.
  Future<void> switchCamera() async {
    await MobileScannerPlatform.instance.stop();

    final CameraFacing cameraDirection;

    // TODO: update the camera facing direction state

    await start(cameraDirection: cameraDirection);
  }

  /// Switches the flashlight on or off.
  ///
  /// Does nothing if the device has no torch.
  ///
  /// Throws if the controller was not initialized.
  Future<void> toggleTorch() async {
    final bool hasTorch;

    if (!hasTorch) {
      return;
    }

    final TorchState newState = torchState.value == TorchState.off ? TorchState.on : TorchState.off;

    // Update the torch state to the new state.
    // When the platform has updated the torch state,
    // it will send an update through the torch state event stream.
    await MobileScannerPlatform.instance.setTorchState();
  }

  @override
  Future<void> dispose() async {
    await MobileScannerPlatform.instance.dispose();
    unawaited(_barcodesController.close());

    super.dispose();
  }
}
