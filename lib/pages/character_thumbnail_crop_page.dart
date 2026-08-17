import 'dart:io';

import 'package:flutter/material.dart';

class ThumbnailCropValue {
  const ThumbnailCropValue({
    required this.focusX,
    required this.focusY,
    required this.scale,
  });

  final double focusX;
  final double focusY;
  final double scale;
}

/// Local-only thumbnail composition editor.
///
/// This page never modifies the source image. It only returns the normalized
/// focal point and scale used by CharacterService to rebuild its cache image.
class CharacterThumbnailCropPage extends StatefulWidget {
  const CharacterThumbnailCropPage({
    super.key,
    required this.imagePath,
    required this.initialFocusX,
    required this.initialFocusY,
    required this.initialScale,
    required this.characterName,
  });

  final String imagePath;
  final double initialFocusX;
  final double initialFocusY;
  final double initialScale;
  final String characterName;

  @override
  State<CharacterThumbnailCropPage> createState() =>
      _CharacterThumbnailCropPageState();
}

class _CharacterThumbnailCropPageState extends State<CharacterThumbnailCropPage> {
  static const double _minScale = 1.0;
  static const double _maxScale = 4.0;

  late double _focusX;
  late double _focusY;
  late double _scale;
  late double _gestureStartFocusX;
  late double _gestureStartFocusY;
  late double _gestureStartScale;
  late Offset _gestureStartFocal;

  @override
  void initState() {
    super.initState();
    _focusX = widget.initialFocusX.clamp(0.0, 1.0);
    _focusY = widget.initialFocusY.clamp(0.0, 1.0);
    _scale = widget.initialScale.clamp(_minScale, _maxScale);
    _gestureStartFocusX = _focusX;
    _gestureStartFocusY = _focusY;
    _gestureStartScale = _scale;
  }

  void _reset() {
    setState(() {
      _focusX = 0.5;
      _focusY = 0.5;
      _scale = 1.0;
    });
  }

  void _save() {
    Navigator.of(context).pop(
      ThumbnailCropValue(focusX: _focusX, focusY: _focusY, scale: _scale),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('调整封面：${widget.characterName}'),
        actions: [
          TextButton(onPressed: _reset, child: const Text('重置')),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final previewWidth = (constraints.maxWidth - 32).clamp(280.0, 520.0);
          final previewHeight = previewWidth * 0.75;
          return SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '拖动调整人物位置，双指缩放。这里只改变角色库里的缩略图构图，不会修改原始封面或导出的角色卡。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LayoutBuilder(
                      builder: (context, frame) {
                        return GestureDetector(
                          onScaleStart: (details) {
                            _gestureStartFocusX = _focusX;
                            _gestureStartFocusY = _focusY;
                            _gestureStartScale = _scale;
                            _gestureStartFocal = details.focalPoint;
                          },
                          onScaleUpdate: (details) {
                            final nextScale = (_gestureStartScale * details.scale)
                                .clamp(_minScale, _maxScale);
                            final scaleRatio = nextScale / _gestureStartScale;
                            final frameSize = frame.biggest;
                            // focalPointDelta 是每帧增量，不能当累计位移用。
                            // 用"当前触点 - 手势开始触点"得到累计位移，否则
                            // 单指拖动时焦点几乎不动（只能缩放、平移卡住）。
                            final offset = details.focalPoint - _gestureStartFocal;
                            setState(() {
                              _scale = nextScale;
                              _focusX = (_gestureStartFocusX -
                                      offset.dx /
                                          (frameSize.width * scaleRatio))
                                  .clamp(0.0, 1.0);
                              _focusY = (_gestureStartFocusY -
                                      offset.dy /
                                          (frameSize.height * scaleRatio))
                                  .clamp(0.0, 1.0);
                            });
                          },
                          child: _CropPreview(
                            imagePath: widget.imagePath,
                            focusX: _focusX,
                            focusY: _focusY,
                            scale: _scale,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '缩放 ${_scale.toStringAsFixed(2)}x',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CropPreview extends StatelessWidget {
  const _CropPreview({
    required this.imagePath,
    required this.focusX,
    required this.focusY,
    required this.scale,
  });

  final String imagePath;
  final double focusX;
  final double focusY;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Text('原始封面不存在，无法调整构图')),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Transform.scale(
            scale: scale,
            alignment: Alignment(focusX * 2 - 1, focusY * 2 - 1),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              alignment: Alignment(focusX * 2 - 1, focusY * 2 - 1),
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
