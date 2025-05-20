import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/book.dart';

class StatisticsCard extends StatefulWidget {
  final int totalBooks;
  final int readBooks;
  final double readingProgress;

  const StatisticsCard({
    super.key,
    required this.totalBooks,
    required this.readBooks,
    required this.readingProgress,
  });

  @override
  State<StatisticsCard> createState() => _StatisticsCardState();
}

class _StatisticsCardState extends State<StatisticsCard> {
  bool _isLoading = true;
  List<MapEntry<String, int>> _topGenres = [];
  List<MapEntry<String, int>> _topAuthors = [];
  int _totalPages = 0;
  int _totalPagesCompleted = 0;
  final ScrollController _scrollController = ScrollController();
  bool _isAtTop = true;
  Map<String, ListProgress> _listProgress = {};

  @override
  void initState() {
    super.initState();
    _loadStatistics();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.offset <= 0 && !_isAtTop) {
      setState(() {
        _isAtTop = true;
      });
    } else if (_scrollController.offset > 0 && _isAtTop) {
      setState(() {
        _isAtTop = false;
      });
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get all books
      final booksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('books')
          .get();

      final books = booksSnapshot.docs.map((doc) {
        final data = doc.data();
        return Book.fromMap(data);
      }).toList();

      // Get all lists
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .get();

      // Initialize list progress
      for (var listDoc in listsSnapshot.docs) {
        final listName = listDoc.data()['name'] as String;
        _listProgress[listName] = ListProgress(
          totalBooks: 0,
          readBooks: 0,
          totalPages: 0,
          readPages: 0,
        );
      }

      // Calculate list progress
      for (var book in books) {
        // Get lists for this book
        final bookListsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('books')
            .doc(book.isbn)
            .collection('lists')
            .get();

        for (var listDoc in bookListsSnapshot.docs) {
          final listName = listDoc.data()['name'] as String;
          if (_listProgress.containsKey(listName)) {
            final progress = _listProgress[listName]!;
            progress.totalBooks++;
            if (book.isRead) {
              progress.readBooks++;
            }
            progress.totalPages += book.pageCount ?? 0;
            if (book.isRead) {
              progress.readPages += book.pageCount ?? 0;
            }
          }
        }
      }

      print('Total books found: ${books.length}');
      print(
          'Books marked as read: ${books.where((book) => book.isRead).length}');

      // Calculate total pages and completed pages
      _totalPages = books.fold(0, (sum, book) => sum + (book.pageCount ?? 0));

      final completedBooks = books.where((book) => book.isRead).toList();
      print('Completed books details:');
      for (var book in completedBooks) {
        print(
            'Book: ${book.title}, Pages: ${book.pageCount}, isRead: ${book.isRead}');
      }

      _totalPagesCompleted =
          completedBooks.fold(0, (sum, book) => sum + (book.pageCount ?? 0));

      print('Total pages: $_totalPages');
      print('Total pages completed: $_totalPagesCompleted');

      // Calculate top genres
      final genreCount = <String, int>{};
      for (var book in books) {
        if (book.categories != null) {
          for (var category in book.categories!) {
            genreCount[category] = (genreCount[category] ?? 0) + 1;
          }
        }
      }
      _topGenres = genreCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _topGenres = _topGenres.take(5).toList();

      // Calculate top authors
      final authorCount = <String, int>{};
      for (var book in books) {
        if (book.authors != null) {
          for (var author in book.authors!) {
            authorCount[author] = (authorCount[author] ?? 0) + 1;
          }
        }
      }
      _topAuthors = authorCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _topAuthors = _topAuthors.take(5).toList();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading statistics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return GestureDetector(
          onVerticalDragEnd: (details) {
            if (_isAtTop && details.primaryVelocity! > 0) {
              Navigator.pop(context);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    controller: scrollController,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Text(
                            'Reading Statistics',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: _StatisticBox(
                                  title: 'Total Books',
                                  value: widget.totalBooks.toString(),
                                  subtitle: 'in your library',
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _StatisticBox(
                                  title: 'Books Read',
                                  value: widget.readBooks.toString(),
                                  subtitle: 'completed',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Overall Progress',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: widget.readingProgress / 100,
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceVariant,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '${widget.readingProgress.toStringAsFixed(1)}%',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: _StatisticBox(
                                  title: 'Total Pages',
                                  value: _totalPages.toString(),
                                  subtitle: 'across all books',
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _StatisticBox(
                                  title: 'Pages Completed',
                                  value: _totalPagesCompleted.toString(),
                                  subtitle: 'from read books',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Theme(
                            data: Theme.of(context).copyWith(
                              dividerTheme: const DividerThemeData(
                                space: 0,
                                thickness: 0,
                              ),
                              expansionTileTheme: const ExpansionTileThemeData(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                              ),
                            ),
                            child: ExpansionTile(
                              title: Text(
                                'List Progress',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              shape: const Border(),
                              collapsedShape: const Border(),
                              children: [
                                ..._listProgress.entries.map((entry) {
                                  final progress = entry.value;
                                  final bookProgress = progress.totalBooks > 0
                                      ? (progress.readBooks /
                                              progress.totalBooks) *
                                          100
                                      : 0.0;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                      const SizedBox(height: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Books Completed',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          const SizedBox(height: 4),
                                          LinearProgressIndicator(
                                            value: bookProgress / 100,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .surfaceVariant,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${progress.readBooks}/${progress.totalBooks} books',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            'Top Genres',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          ..._topGenres.map((genre) => _ListTile(
                                title: genre.key,
                                subtitle: '${genre.value} books',
                              )),
                          const SizedBox(height: 32),
                          Text(
                            'Top Authors',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          ..._topAuthors.map((author) => _ListTile(
                                title: author.key,
                                subtitle: '${author.value} books',
                              )),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class ListProgress {
  int totalBooks;
  int readBooks;
  int totalPages;
  int readPages;

  ListProgress({
    required this.totalBooks,
    required this.readBooks,
    required this.totalPages,
    required this.readPages,
  });
}

class _StatisticBox extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final bool fullWidth;

  const _StatisticBox({
    required this.title,
    required this.value,
    required this.subtitle,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ListTile({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
