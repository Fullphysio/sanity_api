import 'package:sanity_api/sanity_api.dart';

Future<void> main() async {
  final client = SanityClient(
    SanityConfig(
      projectId: 'abc123',
      dataset: 'production',
      apiVersion: '2024-05-03',
    ),
  );

  final exercises = await client.fetch<List<Object?>>(
    r'*[_type == "exercise" && $tag in tags][0...10]{_id, title}',
    params: {'tag': 'shoulder'},
  );
  print('Found ${exercises.length} exercises');

  final response = await client.fetchFull<Object?>('count(*[_type == "exercise"])');
  print('Counted in ${response.ms}ms');

  client.close();
}
