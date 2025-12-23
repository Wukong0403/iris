import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_zustand/flutter_zustand.dart';
import 'package:iris/models/file.dart';
import 'package:iris/store/use_app_store.dart';
import 'package:iris/store/use_play_queue_store.dart';
import 'package:iris/store/use_player_ui_store.dart';
import 'package:iris/utils/logger.dart';
import 'package:iris/utils/platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart';

Future<void> _applyResize(Rect newBounds) async {
  if (await windowManager.isFullScreen() || await windowManager.isMaximized()) {
    return;
  }
  await windowManager.setBounds(newBounds, animate: true);
}

void useResizeWindow() {
  final context = useContext();

  final autoResize = useAppStore().select(context, (state) => state.autoResize);
  final isFullScreen =
      usePlayerUiStore().select(context, (state) => state.isFullScreen);
  final aspectRatio =
      usePlayerUiStore().select(context, (state) => state.aspectRatio);

  final currentPlay = usePlayQueueStore().select(context, (state) {
    final index =
        state.playQueue.indexWhere((e) => e.index == state.currentIndex);
    return index != -1 ? state.playQueue[index] : null;
  });
  final contentType = currentPlay?.file.type ?? ContentType.other;

  final prevIsFullScreen = usePrevious(isFullScreen);
  final prevAspectRatio = usePrevious(aspectRatio);

  useEffect(() {
    if (!isDesktop) return;

    Future<void> performResize() async {
      if (isFullScreen) return;

      if (!autoResize) {
        await windowManager.setAspectRatio(0);
        return;
      }

      if (contentType == ContentType.audio) {
        await windowManager.setAspectRatio(0);
        return;
      }

      if (contentType == ContentType.video) {
        if (aspectRatio <= 0) {
          await windowManager.setAspectRatio(0);
          return;
        }

        await windowManager.setAspectRatio(aspectRatio);
        final oldBounds = await windowManager.getBounds();
        final screen = await getCurrentScreen();
        if (screen == null) return;

        if (oldBounds.size.aspectRatio.toStringAsFixed(2) ==
            aspectRatio.toStringAsFixed(2)) {
          return;
        }

        Size newSize;
        // 横屏视频保持高度不变，竖屏视频保持宽度不变
        logger('Resize rule: Keep dimension, adjust aspect ratio');
        if (aspectRatio >= 1.0) {
          // 横屏视频：保持高度不变，调整宽度
          double newHeight = oldBounds.height;
          double newWidth = newHeight * aspectRatio;
          newSize = Size(newWidth, newHeight);
        } else {
          // 竖屏视频：保持宽度不变，调整高度
          double newWidth = oldBounds.width;
          double newHeight = newWidth / aspectRatio;
          newSize = Size(newWidth, newHeight);
        }

        double maxWidth = screen.frame.width / screen.scaleFactor * 0.85;
        double maxHeight = screen.frame.height / screen.scaleFactor * 0.85;

        if (newSize.width > maxWidth) {
          newSize = Size(maxWidth, maxWidth / aspectRatio);
        }
        if (newSize.height > maxHeight) {
          newSize = Size(maxHeight * aspectRatio, maxHeight);
        }

        // 保持窗口左上角位置不变
        final newPosition = Offset(oldBounds.left, oldBounds.top);

        await _applyResize(Rect.fromLTWH(
            newPosition.dx, newPosition.dy, newSize.width, newSize.height));
      }
    }

    final wasFullScreen = prevIsFullScreen == true;
    if (wasFullScreen && !isFullScreen) {
      Future.delayed(const Duration(milliseconds: 50), performResize);
    } else {
      performResize();
    }

    return null;
  }, [
    autoResize,
    isFullScreen,
    aspectRatio,
    contentType,
  ]);
}
