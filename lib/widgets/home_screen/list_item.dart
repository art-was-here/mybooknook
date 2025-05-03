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
        Card(
          elevation: 2,
          color: widget.accentColor.withOpacity(0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Text(
                      widget.listName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        widget.isExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                      onPressed: () => widget.onToggleExpanded(widget.listName),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: Text(
                  '${widget.bookCount} book${widget.bookCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              SizeTransition(
                sizeFactor: widget.animation,
                child: Column(
                  children: widget.books?.map((bookWithList) {
                        final book = bookWithList.book;
                        final isFirstBook = bookWithList == widget.books?.first;
                        final isLastBook = bookWithList == widget.books?.last;

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16.0),
                          leading: book.imageUrl != null
                              ? Image.network(
                                  book.imageUrl!,
                                  width: 50,
                                  height: 75,
                                  fit: BoxFit.cover,
                                  errorBuilder: (BuildContext imageContext,
                                          Object error,
                                          StackTrace? stackTrace) =>
                                      const Icon(Icons.book, size: 50),
                                )
                              : const Icon(Icons.book, size: 50),
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
      ],
    );
  }
}
