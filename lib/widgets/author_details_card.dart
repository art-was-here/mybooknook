import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthorDetailsCard extends StatefulWidget {
  final String authorName;

  const AuthorDetailsCard({
    super.key,
    required this.authorName,
  });

  @override
  State<AuthorDetailsCard> createState() => _AuthorDetailsCardState();
}

class _AuthorDetailsCardState extends State<AuthorDetailsCard> {
  bool _isLoading = true;
  String? _biography;
  String? _imageUrl;
  String? _error;
  List<Map<String, dynamic>> _otherBooks = [];
  bool _isLoadingBooks = false;
  ScrollController? _scrollController;
  bool _canDismiss = false;
  String? _birthDate;
  String? _deathDate;
  List<String>? _alternateNames;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController?.addListener(_handleScroll);
    _fetchAuthorDetails();
  }

  @override
  void dispose() {
    _scrollController?.removeListener(_handleScroll);
    _scrollController?.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController?.position.pixels == 0) {
      setState(() {
        _canDismiss = true;
      });
    } else if (_canDismiss) {
      setState(() {
        _canDismiss = false;
      });
    }
  }

  Future<void> _fetchAuthorDetails() async {
    try {
      // Use Open Library API to get author details
      final searchUrl =
          'https://openlibrary.org/search/authors.json?q=${Uri.encodeComponent(widget.authorName)}';
      print('Searching author with URL: $searchUrl');

      final response = await http.get(Uri.parse(searchUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Search response: ${response.body}');

        if (data['docs'] != null && data['docs'].isNotEmpty) {
          final author = data['docs'][0];
          final authorKey = author['key'];
          print('Found author key: $authorKey');

          // Fetch author details
          final detailsUrl = 'https://openlibrary.org/authors/$authorKey.json';
          print('Fetching author details from: $detailsUrl');

          final detailsResponse = await http.get(Uri.parse(detailsUrl));

          if (detailsResponse.statusCode == 200) {
            final authorData = json.decode(detailsResponse.body);
            print('Author details response: ${detailsResponse.body}');

            setState(() {
              _biography =
                  authorData['bio']?['value'] ?? 'No biography available';
              _imageUrl = authorData['photos']?.isNotEmpty == true
                  ? 'https://covers.openlibrary.org/a/id/${authorData['photos'][0]}-L.jpg'
                  : null;
              _birthDate = authorData['birth_date'];
              _deathDate = authorData['death_date'];
              _alternateNames = authorData['alternate_names']?.cast<String>();
              _isLoading = false;
            });

            // Fetch author's works
            await _fetchAuthorWorks(authorKey);
          } else {
            print(
                'Failed to load author details. Status code: ${detailsResponse.statusCode}');
            setState(() {
              _error = 'Failed to load author details';
              _isLoading = false;
            });
          }
        } else {
          print('No author found in search results');
          setState(() {
            _error = 'Author not found';
            _isLoading = false;
          });
        }
      } else {
        print(
            'Failed to search for author. Status code: ${response.statusCode}');
        setState(() {
          _error = 'Failed to search for author';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching author details: $e');
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchAuthorWorks(String authorKey) async {
    try {
      setState(() {
        _isLoadingBooks = true;
      });

      final worksUrl = 'https://openlibrary.org/authors/$authorKey/works.json';
      final response = await http.get(Uri.parse(worksUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['entries'] != null) {
          final works = data['entries'] as List;
          final books = works.take(10).map((work) {
            final coverId =
                work['covers']?.isNotEmpty == true ? work['covers'][0] : null;
            return {
              'title': work['title'],
              'coverUrl': coverId != null
                  ? 'https://covers.openlibrary.org/b/id/$coverId-M.jpg'
                  : null,
              'key': work['key'],
            };
          }).toList();

          setState(() {
            _otherBooks = books;
            _isLoadingBooks = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching author works: $e');
      setState(() {
        _isLoadingBooks = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.5, 0.7, 0.9, 0.95],
      builder: (context, scrollController) => WillPopScope(
        onWillPop: () async {
          if (_scrollController?.position.pixels != 0) {
            _scrollController?.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
            return false;
          }
          return true;
        },
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      widget.authorName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                _error!,
                                style: Theme.of(context).textTheme.bodyLarge,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: _scrollController,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Card(
                                  elevation: 4,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 10.0),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        10.0, 10.0, 10.0, 5.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_imageUrl != null)
                                          Center(
                                            child: GestureDetector(
                                              onTap: () {
                                                showDialog(
                                                  context: context,
                                                  builder:
                                                      (BuildContext context) {
                                                    return Dialog(
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Stack(
                                                            children: [
                                                              Image.network(
                                                                _imageUrl!,
                                                                fit: BoxFit
                                                                    .contain,
                                                                errorBuilder: (context,
                                                                        error,
                                                                        stackTrace) =>
                                                                    const Icon(
                                                                        Icons
                                                                            .person,
                                                                        size:
                                                                            200),
                                                              ),
                                                              Positioned(
                                                                top: 8,
                                                                right: 8,
                                                                child:
                                                                    IconButton(
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .close),
                                                                  onPressed: () =>
                                                                      Navigator.of(
                                                                              context)
                                                                          .pop(),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                );
                                              },
                                              child: ClipOval(
                                                child: Image.network(
                                                  _imageUrl!,
                                                  width: 200,
                                                  height: 200,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                          stackTrace) =>
                                                      const Icon(Icons.person,
                                                          size: 200),
                                                ),
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 16),
                                        if (_birthDate != null ||
                                            _deathDate != null)
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Life',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                [
                                                  if (_birthDate != null)
                                                    'Born: $_birthDate',
                                                  if (_deathDate != null)
                                                    'Died: $_deathDate',
                                                ].join('\n'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                          ),
                                        if (_alternateNames != null &&
                                            _alternateNames!.isNotEmpty)
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Also Known As',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _alternateNames!.join(', '),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                          ),
                                        Text(
                                          'Biography',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _biography ??
                                              'No biography available',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (_otherBooks.isNotEmpty)
                                  Card(
                                    elevation: 4,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 10.0),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          10.0, 10.0, 10.0, 5.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Other Books by ${widget.authorName}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            height: 200,
                                            child: _isLoadingBooks
                                                ? const Center(
                                                    child:
                                                        CircularProgressIndicator())
                                                : ListView.builder(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    itemCount:
                                                        _otherBooks.length,
                                                    itemBuilder:
                                                        (context, index) {
                                                      final book =
                                                          _otherBooks[index];
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                right: 16),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Container(
                                                              width: 120,
                                                              height: 160,
                                                              decoration:
                                                                  BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                                color: Colors
                                                                    .grey[200],
                                                                image: book['coverUrl'] !=
                                                                        null
                                                                    ? DecorationImage(
                                                                        image: NetworkImage(
                                                                            book['coverUrl']),
                                                                        fit: BoxFit
                                                                            .cover,
                                                                      )
                                                                    : null,
                                                              ),
                                                              child: book['coverUrl'] ==
                                                                      null
                                                                  ? const Icon(
                                                                      Icons
                                                                          .book,
                                                                      size: 48)
                                                                  : null,
                                                            ),
                                                            const SizedBox(
                                                                height: 8),
                                                            SizedBox(
                                                              width: 120,
                                                              child: Text(
                                                                book['title'],
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodySmall,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
