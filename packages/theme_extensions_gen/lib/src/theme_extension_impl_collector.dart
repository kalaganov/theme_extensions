import 'dart:async' show FutureOr;
import 'dart:convert' show jsonEncode;

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart' show BuildStep, Builder;
import 'package:meta/meta.dart' show immutable, visibleForTesting;
import 'package:source_gen/source_gen.dart' show LibraryReader, TypeChecker;
import 'package:theme_extensions_gen/src/models/collected_impl.dart';
import 'package:theme_extensions_gen/src/models/collected_impl_list.dart';
import 'package:theme_extensions_gen/src/validators/theme_extension_impl_validator.dart';
import 'package:theme_extensions_gen_annotations/theme_extensions_gen_annotations.dart';

//ignore_for_file: deprecated_member_use

/// Collects all elements annotated with `@ThemeExtensionImpl`
/// and writes their names and import URI to a `.theme_impl.json` file.
///
/// This builder runs in the first step of the generation process.
/// The output is used by the second step to produce the final extension list.
@immutable
final class ThemeExtensionImplCollector extends Builder {
  /// Creates a [ThemeExtensionImplCollector] using parsed build configuration.
  ThemeExtensionImplCollector();

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;

    final isLibrary = await buildStep.resolver.isLibrary(inputId);
    if (!isLibrary) return;

    final lib = await buildStep.inputLibrary;

    final reader = LibraryReader(lib);
    final annotatedElements = reader.annotatedWith(
      const TypeChecker.fromRuntime(ThemeExtensionImpl),
    );
    if (annotatedElements.isEmpty) return;

    const validator = ThemeExtensionImplValidator();
    final items = <CollectedImpl>[];

    for (final annotated in annotatedElements) {
      validator.validateElement(annotated.element);

      final group = annotated.annotation.peek('group')?.stringValue;
      final prefix = resolveNamePrefix(annotated.element);
      final name = resolveElementName(annotated.element);

      final impl = CollectedImpl(
        group: group,
        importUri: inputId.uri.toString(),
        name: '$prefix$name',
      );
      items.add(impl);
    }
    final list = CollectedImplList(data: items);

    await buildStep.writeAsString(
      inputId.changeExtension('.theme_impl.json'),
      jsonEncode(list.toJson()),
    );
  }

  /// nodoc
  @visibleForTesting
  String resolveNamePrefix(Element element) {
    return switch (element) {
      FunctionElement(:final returnType) =>
        returnType.isDartCoreList ? '...' : '',
      PropertyAccessorElement(:final returnType) =>
        returnType.isDartCoreList ? '...' : '',
      TopLevelVariableElement(:final type) => type.isDartCoreList ? '...' : '',
      _ => throw StateError('Unexpected element type: ${element.runtimeType}'),
    };
  }

  /// nodoc
  @visibleForTesting
  String resolveElementName(Element element) {
    return switch (element) {
      FunctionElement(:final displayName) => '$displayName()',
      PropertyAccessorElement(:final displayName) => displayName,
      TopLevelVariableElement(:final displayName) => displayName,
      _ => throw StateError('Unexpected element type: ${element.runtimeType}'),
    };
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.theme_impl.json'],
      };
}
