import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';

class BookDetailsCard {
  static void show(BuildContext context, Book book, String selectedListName,
      BookService bookService, String? selectedListId) {
    print('Showing details for book: ${book.title}');
    bool isInfoExpanded = false;
    bool isDescriptionExpanded = false;
    bool isDeleting = false;
    int currentRating = book.userRating;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (modalContext, setModalState) => Container(
            decoration: BoxDecoration(
              color: Theme.of(modalContext).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      book.title,
                      style: Theme.of(modalContext).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (book.imageUrl != null)
                      Center(
                        child: Image.network(
                          book.imageUrl!,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.broken_image, size: 100),
                        ),
                      )
                    else
                      const Center(child: Icon(Icons.book, size: 100)),
                    const SizedBox(height: 8),
                    Center(child: Text('ISBN: ${book.isbn}')),
                    const SizedBox(height: 16),
                    Text(
                      'Authors:',
                      style: Theme.of(modalContext).textTheme.titleMedium,
                    ),
                    Text(book.authors?.join(', ') ?? 'Unknown'),
                    const SizedBox(height: 16),
                    Text(
                      'Genres:',
                      style: Theme.of(modalContext).textTheme.titleMedium,
                    ),
                    Text(book.categories?.join(', ') ?? 'None'),
                    const SizedBox(height: 16),
                    if (!isInfoExpanded)
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            isInfoExpanded = true;
                          });
                        },
                        child: const Text('Expand'),
                      ),
                    if (isInfoExpanded) ...[
                      Text(
                        'Publisher:',
                        style: Theme.of(modalContext).textTheme.titleMedium,
                      ),
                      Text(book.publisher ?? 'Unknown'),
                      const SizedBox(height: 16),
                      Text(
                        'Published Date:',
                        style: Theme.of(modalContext).textTheme.titleMedium,
                      ),
                      Text(book.publishedDate ?? 'Unknown'),
                      const SizedBox(height: 16),
                      Text(
                        'Page Count:',
                        style: Theme.of(modalContext).textTheme.titleMedium,
                      ),
                      Text(book.pageCount?.toString() ?? 'Unknown'),
                      const SizedBox(height: 16),
                      Text(
                        'Average Rating:',
                        style: Theme.of(modalContext).textTheme.titleMedium,
                      ),
                      Text(book.averageRating != null
                          ? '${book.averageRating} / 5'
                          : 'No rating available'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            isInfoExpanded = false;
                          });
                        },
                        child: const Text('Collapse'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Description:',
                      style: Theme.of(modalContext).textTheme.titleMedium,
                    ),
                    Text(
                      book.description,
                      maxLines: isDescriptionExpanded ? null : 6,
                      overflow:
                          isDescriptionExpanded ? null : TextOverflow.ellipsis,
                    ),
                    if (book.description.length > 100)
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            isDescriptionExpanded = !isDescriptionExpanded;
                          });
                        },
                        child:
                            Text(isDescriptionExpanded ? 'Collapse' : 'Expand'),
                      ),
                    const SizedBox(height: 16),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Your Rating:',
                            style: Theme.of(modalContext).textTheme.titleMedium,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              return IconButton(
                                icon: Icon(
                                  index < currentRating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: index < currentRating
                                      ? Colors.amber
                                      : Colors.grey,
                                ),
                                onPressed: () async {
                                  final newRating = index + 1;
                                  print(
                                      'Setting rating to $newRating stars for ${book.title}');
                                  setModalState(() {
                                    currentRating = newRating;
                                  });
                                  try {
                                    await bookService.updateBookRating(
                                        book.isbn,
                                        book.title,
                                        newRating,
                                        selectedListName,
                                        selectedListId);
                                  } catch (e) {
                                    setModalState(() {
                                      currentRating =
                                          book.userRating; // Revert on error
                                    });
                                  }
                                },
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: isDeleting
                              ? null
                              : () async {
                                  print(
                                      'Delete button pressed for: ${book.title}');
                                  setModalState(() {
                                    isDeleting = true;
                                    print('Set isDeleting = true');
                                  });
                                  try {
                                    await bookService.deleteBook(
                                        book.isbn,
                                        book.title,
                                        selectedListName,
                                        selectedListId);
                                    print('Delete operation completed');
                                    if (modalContext.mounted) {
                                      ScaffoldMessenger.of(modalContext)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Book deleted from $selectedListName: ${book.title}'),
                                        ),
                                      );
                                    }
                                  } catch (e, stackTrace) {
                                    print('Error in delete operation: $e');
                                    print('Stack trace: $stackTrace');
                                    if (modalContext.mounted) {
                                      ScaffoldMessenger.of(modalContext)
                                          .showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                    }
                                  } finally {
                                    print(
                                        'Entering finally block for book delete');
                                    if (modalContext.mounted) {
                                      setModalState(() {
                                        isDeleting = false;
                                        print('Reset isDeleting = false');
                                      });
                                      print('Scheduling modal dismissal');
                                      await Future.delayed(
                                          const Duration(milliseconds: 100));
                                      if (modalContext.mounted) {
                                        print('Dismissing book details sheet');
                                        Navigator.of(modalContext).pop();
                                      } else {
                                        print(
                                            'Modal context not mounted, cannot pop');
                                      }
                                    } else {
                                      print(
                                          'Modal context not mounted in finally block');
                                    }
                                  }
                                },
                          child: isDeleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                        ),
                        TextButton(
                          onPressed: () {
                            print('OK button pressed, dismissing book details');
                            Navigator.of(modalContext).pop();
                          },
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
