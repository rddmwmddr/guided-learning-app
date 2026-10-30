import 'package:flutter/material.dart';

/// 完成排版后跟随底部；用户翻阅旧消息时暂停跟随。
class TranscriptScroller extends StatefulWidget {
  const TranscriptScroller({super.key, required this.children});
  final List<Widget> children;

  @override
  State<TranscriptScroller> createState() => _TranscriptScrollerState();
}

class _TranscriptScrollerState extends State<TranscriptScroller> {
  final _scroll = ScrollController();
  bool _following = true;
  bool _scheduled = false;
  bool _animating = false;
  bool _userScrolling = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(TranscriptScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (!_following || _scheduled || _animating) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_following || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if ((target - _scroll.offset).abs() < 1) return;
      final reduced = MediaQuery.disableAnimationsOf(context);
      if (reduced) {
        _scroll.jumpTo(target);
      } else {
        _animating = true;
        _scroll
            .animateTo(
              target,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              _animating = false;
              // 动画过程中键盘、气泡或底部控件可能继续改变高度。
              if (mounted &&
                  _following &&
                  _scroll.hasClients &&
                  _scroll.position.extentAfter > 1) {
                _schedule();
              }
            });
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _schedule();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notice) {
            if (notice.depth != 0) return false;
            if (notice is ScrollStartNotification &&
                notice.dragDetails != null) {
              _userScrolling = true;
            }
            if (_userScrolling) {
              final follow = notice.metrics.extentAfter < 64;
              if (follow != _following) setState(() => _following = follow);
              if (notice is ScrollEndNotification) _userScrolling = false;
            }
            return false;
          },
          child: SingleChildScrollView(
            key: const Key('transcriptScroll'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
        ),
      ),
      if (!_following)
        Positioned(
          right: 12,
          bottom: 8,
          child: FilledButton.tonalIcon(
            onPressed: () {
              setState(() => _following = true);
              _schedule();
            },
            icon: const Icon(Icons.arrow_downward, size: 18),
            label: const Text('回到最新'),
          ),
        ),
    ],
  );
}
