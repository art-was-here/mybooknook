import 'package:flutter/material.dart';
import '../../models/book.dart';
import 'book_with_list.dart';

class ListItem extends StatefulWidget {
  final String listName;
  final int bookCount;
  final List<BookWithList>? books;
  final bool isExpanded;
  final Animation<double> animation;
  final Color accentColor;
  final Function(String) onToggleExpanded;
  final Function(BuildContext, Book) onBookTap;

  const ListItem({
    super.key,
    required this.listName,
    required this.bookCount,
    required this.books,
    required this.isExpanded,
    required this.animation,
    required this.accentColor,
    required this.onToggleExpanded,
    required this.onBookTap,
  });

  @override
  State<ListItem> createState() => _ListItemState();
}

class _ListItemState extends State<ListItem> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0.0),
          child: Card(
            elevation: 2,
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section with book covers, list name, count, and expand arrow
                InkWell(
                  onTap: () => widget.onToggleExpanded(widget.listName),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        // Book covers grid (2x2)
                        _buildCoverGrid(),
                        const SizedBox(width: 16),
                        // List name and book count
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.listName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.bookCount} book${widget.bookCount == 1 ? '' : 's'}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        // Expand/collapse icon
                        Icon(
                          widget.isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                      ],
                    ),
                  ),
                ),

                // Expandable book list
                SizeTransition(
                  sizeFactor: widget.animation,
                  child: Column(
                    children: widget.books?.map((bookWithList) {
                          final book = bookWithList.book;
                          return ListTile(
                            dense: true,
                            minVerticalPadding: 0,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 0.0),
                            leading: book.imageUrl != null
                                ? Container(
                                    width: 50,
                                    height: 75,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Image.network(
                                      book.imageUrl!,
                                      width: 50,
                                      height: 75,
                                      fit: BoxFit.cover,
                                      errorBuilder: (BuildContext imageContext,
                                              Object error,
                                              StackTrace? stackTrace) =>
                                          const Icon(Icons.book, size: 50),
                                    ),
                                  )
                                : Container(
                                    width: 50,
                                    height: 75,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.book, size: 50),
                                  ),
                            title: Text(book.title),
                            subtitle: Text(
                              book.authors?.join(', ') ?? 'Unknown Author',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => widget.onBookTap(context, book),
                          );
                        }).toList() ??
                        [],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCoverGrid() {
    // Container for the 2x2 grid of book covers
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: widget.books == null || widget.books!.isEmpty
          ? const Center(child: Icon(Icons.menu_book, size: 24))
          : GridView.count(
              crossAxisCount: 2,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(
                // Use min to avoid overflow if less than 4 books
                4.clamp(0, widget.books!.length),
                (index) {
                  // Only show up to 4 books
                  if (index >= widget.books!.length) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.menu_book, size: 12),
                    );
                  }

                  final book = widget.books![index].book;
                  return Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      image: book.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(book.imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: book.imageUrl == null ? Colors.grey[300] : null,
                    ),
                    child: book.imageUrl == null
                        ? const Center(child: Icon(Icons.book, size: 12))
                        : null,
                  );
                },
              ),
            ),
    );
  }
}
