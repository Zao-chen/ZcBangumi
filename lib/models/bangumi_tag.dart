import 'subject.dart';

class BangumiTag {
  final String name;
  final int count;
  final String href;

  const BangumiTag({
    required this.name,
    required this.count,
    required this.href,
  });
}

class BangumiTagSubject {
  final SlimSubject subject;
  final String info;
  final int ratingTotal;

  const BangumiTagSubject({
    required this.subject,
    required this.info,
    required this.ratingTotal,
  });
}

class BangumiTagPageResult {
  final List<BangumiTag> tags;
  final int page;
  final int totalPages;

  const BangumiTagPageResult({
    required this.tags,
    required this.page,
    required this.totalPages,
  });
}

class BangumiTagSubjectPageResult {
  final List<BangumiTagSubject> subjects;
  final int page;
  final int totalPages;

  const BangumiTagSubjectPageResult({
    required this.subjects,
    required this.page,
    required this.totalPages,
  });
}
