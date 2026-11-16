import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Lets files be dragged onto [builder]'s area from Explorer or Finder.
/// [builder] gets whether a drag is over the area, to show it will accept
/// the drop.
class KycDropTarget extends StatefulWidget {
  const KycDropTarget({
    super.key,
    required this.onDropped,
    required this.builder,
  });

  final ValueChanged<List<XFile>> onDropped;
  final Widget Function(BuildContext context, bool hovering) builder;

  @override
  State<KycDropTarget> createState() => _KycDropTargetState();
}

class _KycDropTargetState extends State<KycDropTarget> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (_hovering != value) setState(() => _hovering = value);
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: (details) {
        _setHovering(false);
        widget.onDropped(details.files);
      },
      child: widget.builder(context, _hovering),
    );
  }
}
