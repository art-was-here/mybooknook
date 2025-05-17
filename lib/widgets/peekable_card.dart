import 'package:flutter/material.dart';

class PeekableCard extends StatefulWidget {
  final Widget child;
  final double peekHeight;
  final double expandedHeight;
  final Color backgroundColor;

  const PeekableCard({
    super.key,
    required this.child,
    this.peekHeight = 60.0,
    this.expandedHeight = 300.0,
    this.backgroundColor = Colors.white,
  });

  static bool? of(BuildContext context) {
    final state = context.findAncestorStateOfType<_PeekableCardState>();
    return state?._isExpanded;
  }

  @override
  State<PeekableCard> createState() => _PeekableCardState();
}

class _PeekableCardState extends State<PeekableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use an absolutely minimal implementation with fixed height
    return GestureDetector(
      onTap: _toggleExpanded,
      onVerticalDragEnd: (_) => _toggleExpanded(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: _isExpanded ? widget.expandedHeight : widget.peekHeight,
        decoration: BoxDecoration(
          color: Color.lerp(widget.backgroundColor, Colors.black, 0.15) ??
              widget.backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Column(
          children: [
            // Small box above chevron
            Container(
              height: 5,
              width: double.infinity,
              color: Colors.transparent,
            ),
            // Handle with chevron icon
            Container(
              height: 20,
              width: double.infinity,
              alignment: Alignment.center,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 300),
                turns: _isExpanded ? 0.5 : 0,
                child: Icon(
                  Icons.keyboard_arrow_up,
                  color: Colors.grey[600],
                  size: 30,
                ),
              ),
            ),

            // Content - only visible when expanded
            if (_isExpanded)
              Expanded(
                child: widget.child,
              ),
          ],
        ),
      ),
    );
  }
}
