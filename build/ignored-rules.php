<?php

declare(strict_types = 1);

// phpcs:ignoreFile SlevomatCodingStandard.Files.FileLength.FileTooLong

use Rector\Arguments\Rector\ClassMethod\ArgumentAdderRector;
use Rector\Arguments\Rector\ClassMethod\ReplaceArgumentDefaultValueRector;
use Rector\Arguments\Rector\FuncCall\FunctionArgumentDefaultValueReplacerRector;
use Rector\Arguments\Rector\MethodCall\RemoveMethodCallParamRector;
use Rector\Assert\Rector\ClassMethod\AddAssertArrayFromClassMethodDocblockRector;
use Rector\Carbon\Rector\FuncCall\DateFuncCallToCarbonRector;
use Rector\Carbon\Rector\FuncCall\TimeFuncCallToCarbonRector;
use Rector\Carbon\Rector\MethodCall\DateTimeMethodCallToCarbonRector;
use Rector\Carbon\Rector\New_\DateTimeInstanceToCarbonRector;
use Rector\CodeQuality\Rector\BooleanAnd\RemoveUselessIsObjectCheckRector;
use Rector\CodeQuality\Rector\BooleanAnd\SimplifyEmptyArrayCheckRector;
use Rector\CodeQuality\Rector\BooleanNot\ReplaceConstantBooleanNotRector;
use Rector\CodeQuality\Rector\BooleanNot\ReplaceMultipleBooleanNotRector;
use Rector\CodeQuality\Rector\BooleanNot\SimplifyDeMorganBinaryRector;
use Rector\CodeQuality\Rector\Class_\ConvertStaticToSelfRector;
use Rector\CodeQuality\Rector\Class_\DynamicDocBlockPropertyToNativePropertyRector;
use Rector\CodeQuality\Rector\Class_\RemoveReadonlyPropertyVisibilityOnReadonlyClassRector;
use Rector\CodeQuality\Rector\ClassMethod\ExplicitReturnNullRector;
use Rector\CodeQuality\Rector\ClassMethod\OptionalParametersAfterRequiredRector;
use Rector\CodeQuality\Rector\Equal\UseIdenticalOverEqualWithSameTypeRector;
use Rector\CodeQuality\Rector\For_\ForRepeatedCountToOwnVariableRector;
use Rector\CodeQuality\Rector\FuncCall\CallUserFuncWithArrowFunctionToInlineRector;
use Rector\CodeQuality\Rector\FuncCall\InlineIsAInstanceOfRector;
use Rector\CodeQuality\Rector\FuncCall\IsAWithStringWithThirdArgumentRector;
use Rector\CodeQuality\Rector\FuncCall\SetTypeToCastRector;
use Rector\CodeQuality\Rector\FuncCall\SimplifyFuncGetArgsCountRector;
use Rector\CodeQuality\Rector\FuncCall\SimplifyStrposLowerRector;
use Rector\CodeQuality\Rector\FuncCall\SingleInArrayToCompareRector;
use Rector\CodeQuality\Rector\FuncCall\SortNamedParamRector;
use Rector\CodeQuality\Rector\Identical\BooleanNotIdenticalToNotIdenticalRector;
use Rector\CodeQuality\Rector\Identical\FlipTypeControlToUseExclusiveTypeRector;
use Rector\CodeQuality\Rector\Identical\SimplifyArraySearchRector;
use Rector\CodeQuality\Rector\Identical\SimplifyBoolIdenticalTrueRector;
use Rector\CodeQuality\Rector\Identical\SimplifyConditionsRector;
use Rector\CodeQuality\Rector\Identical\StrlenZeroToIdenticalEmptyStringRector;
use Rector\CodeQuality\Rector\If_\CompleteMissingIfElseBracketRector;
use Rector\CodeQuality\Rector\If_\ExplicitBoolCompareRector;
use Rector\CodeQuality\Rector\Include_\AbsolutizeRequireAndIncludePathRector;
use Rector\CodeQuality\Rector\Isset_\IssetOnPropertyObjectToPropertyExistsRector;
use Rector\CodeQuality\Rector\New_\NewStaticToNewSelfRector;
use Rector\CodeQuality\Rector\Switch_\SingularSwitchToIfRector;
use Rector\CodeQuality\Rector\Ternary\NumberCompareToMaxFuncCallRector;
use Rector\CodeQuality\Rector\Ternary\TernaryImplodeToImplodeRector;
use Rector\CodingStyle\Rector\ArrowFunction\ArrowFunctionDelegatingCallToFirstClassCallableRector;
use Rector\CodingStyle\Rector\ArrowFunction\StaticArrowFunctionRector;
use Rector\CodingStyle\Rector\Assign\SplitDoubleAssignRector;
use Rector\CodingStyle\Rector\Catch_\CatchExceptionNameMatchingTypeRector;
use Rector\CodingStyle\Rector\ClassConst\RemoveFinalFromConstRector;
use Rector\CodingStyle\Rector\ClassConst\SplitGroupedClassConstantsRector;
use Rector\CodingStyle\Rector\ClassMethod\FuncGetArgsToVariadicParamRector;
use Rector\CodingStyle\Rector\ClassMethod\NewlineBeforeNewAssignSetRector;
use Rector\CodingStyle\Rector\Closure\ClosureDelegatingCallToFirstClassCallableRector;
use Rector\CodingStyle\Rector\Closure\StaticClosureRector;
use Rector\CodingStyle\Rector\Encapsed\WrapEncapsedVariableInCurlyBracesRector;
use Rector\CodingStyle\Rector\Enum_\EnumCaseToPascalCaseRector;
use Rector\CodingStyle\Rector\FuncCall\CallUserFuncArrayToVariadicRector;
use Rector\CodingStyle\Rector\FuncCall\CallUserFuncToMethodCallRector;
use Rector\CodingStyle\Rector\FuncCall\ClosureFromCallableToFirstClassCallableRector;
use Rector\CodingStyle\Rector\FuncCall\CountArrayToEmptyArrayComparisonRector;
use Rector\CodingStyle\Rector\FuncCall\FunctionFirstClassCallableRector;
use Rector\CodingStyle\Rector\FuncCall\StrictArraySearchRector;
use Rector\CodingStyle\Rector\FuncCall\VersionCompareFuncCallToConstantRector;
use Rector\CodingStyle\Rector\FunctionLike\FunctionLikeToFirstClassCallableRector;
use Rector\CodingStyle\Rector\If_\NullableCompareToNullRector;
use Rector\CodingStyle\Rector\PostInc\PostIncDecToPreIncDecRector;
use Rector\CodingStyle\Rector\Property\SplitGroupedPropertiesRector;
use Rector\CodingStyle\Rector\Stmt\NewlineAfterStatementRector;
use Rector\CodingStyle\Rector\Stmt\RemoveUselessAliasInUseStatementRector;
use Rector\CodingStyle\Rector\String_\SymplifyQuoteEscapeRector;
use Rector\CodingStyle\Rector\String_\UseClassKeywordForClassNameResolutionRector;
use Rector\CodingStyle\Rector\Ternary\TernaryConditionVariableAssignmentRector;
use Rector\CodingStyle\Rector\Use_\SeparateMultiUseImportsRector;
use Rector\DeadCode\Rector\Array_\RemoveDuplicatedArrayKeyRector;
use Rector\DeadCode\Rector\Block\ReplaceBlockToItsStmtsRector;
use Rector\DeadCode\Rector\BooleanAnd\RemoveAndTrueRector;
use Rector\DeadCode\Rector\ClassLike\RemoveAnnotationRector;
use Rector\DeadCode\Rector\ClassLike\RemoveTypedPropertyNonMockDocblockRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveArgumentFromDefaultParentCallRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveNullTagValueNodeRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPublicMethodParameterRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUselessAssignFromPropertyPromotionRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUselessReturnExprInConstructRector;
use Rector\DeadCode\Rector\Concat\RemoveConcatAutocastRector;
use Rector\DeadCode\Rector\ConstFetch\RemovePhpVersionIdCheckRector;
use Rector\DeadCode\Rector\Expression\RemoveDeadStmtRector;
use Rector\DeadCode\Rector\Expression\SimplifyMirrorAssignRector;
use Rector\DeadCode\Rector\For_\RemoveDeadContinueRector;
use Rector\DeadCode\Rector\For_\RemoveDeadLoopRector;
use Rector\DeadCode\Rector\Foreach_\RemoveUnusedForeachKeyRector;
use Rector\DeadCode\Rector\FuncCall\RemoveFilterVarOnExactTypeRector;
use Rector\DeadCode\Rector\If_\RemoveAlwaysTrueIfConditionRector;
use Rector\DeadCode\Rector\If_\RemoveDeadInstanceOfRector;
use Rector\DeadCode\Rector\If_\RemoveTypedPropertyDeadInstanceOfRector;
use Rector\DeadCode\Rector\If_\RemoveUnusedNonEmptyArrayBeforeForeachRector;
use Rector\DeadCode\Rector\If_\SimplifyIfElseWithSameContentRector;
use Rector\DeadCode\Rector\If_\UnwrapFutureCompatibleIfPhpVersionRector;
use Rector\DeadCode\Rector\MethodCall\RemoveNullArgOnNullDefaultParamRector;
use Rector\DeadCode\Rector\Plus\RemoveDeadZeroAndOneOperationRector;
use Rector\DeadCode\Rector\Property\RemoveUnusedPrivatePropertyRector;
use Rector\DeadCode\Rector\PropertyProperty\RemoveNullPropertyInitializationRector;
use Rector\DeadCode\Rector\Return_\RemoveDeadConditionAboveReturnRector;
use Rector\DeadCode\Rector\Switch_\RemoveDuplicatedCaseInSwitchRector;
use Rector\EarlyReturn\Rector\Foreach_\ChangeNestedForeachIfsToEarlyContinueRector;
use Rector\EarlyReturn\Rector\If_\ChangeNestedIfsToEarlyReturnRector;
use Rector\EarlyReturn\Rector\If_\ChangeOrIfContinueToMultiContinueRector;
use Rector\EarlyReturn\Rector\Return_\PreparedValueToEarlyReturnRector;
use Rector\EarlyReturn\Rector\Return_\ReturnBinaryOrToEarlyReturnRector;
use Rector\Instanceof_\Rector\Ternary\FlipNegatedTernaryInstanceofRector;
use Rector\Naming\Rector\Assign\RenameVariableToMatchMethodCallReturnTypeRector;
use Rector\Naming\Rector\ClassMethod\RenameParamToMatchTypeRector;
use Rector\Naming\Rector\ClassMethod\RenameVariableToMatchNewTypeRector;
use Rector\Naming\Rector\Foreach_\RenameForeachValueVariableToMatchExprVariableRector;
use Rector\Naming\Rector\Foreach_\RenameForeachValueVariableToMatchMethodCallReturnTypeRector;
use Rector\NetteUtils\Rector\StaticCall\UtilsJsonStaticCallNamedArgRector;
use Rector\Php52\Rector\Property\VarToPublicPropertyRector;
use Rector\Php52\Rector\Switch_\ContinueToBreakInSwitchRector;
use Rector\Php53\Rector\FuncCall\DirNameFileConstantToDirConstantRector;
use Rector\Php53\Rector\Variable\ReplaceHttpServerVarsByServerRector;
use Rector\Php54\Rector\Array_\LongArrayToShortArrayRector;
use Rector\Php54\Rector\Break_\RemoveZeroBreakContinueRector;
use Rector\Php54\Rector\FuncCall\RemoveReferenceFromCallRector;
use Rector\Php55\Rector\Class_\ClassConstantToSelfClassRector;
use Rector\Php55\Rector\ClassConstFetch\StaticToSelfOnFinalClassRector;
use Rector\Php55\Rector\FuncCall\GetCalledClassToSelfClassRector;
use Rector\Php55\Rector\FuncCall\GetCalledClassToStaticClassRector;
use Rector\Php55\Rector\FuncCall\PregReplaceEModifierRector;
use Rector\Php55\Rector\String_\StringClassNameToClassConstantRector;
use Rector\Php56\Rector\FuncCall\PowToExpRector;
use Rector\Php70\Rector\Assign\ListSplitStringRector;
use Rector\Php70\Rector\Assign\ListSwapArrayOrderRector;
use Rector\Php70\Rector\Break_\BreakNotInLoopOrSwitchToReturnRector;
use Rector\Php70\Rector\ClassMethod\Php4ConstructorRector;
use Rector\Php70\Rector\FuncCall\CallUserMethodRector;
use Rector\Php70\Rector\FuncCall\EregToPregMatchRector;
use Rector\Php70\Rector\FuncCall\MultiDirnameRector;
use Rector\Php70\Rector\FuncCall\RandomFunctionRector;
use Rector\Php70\Rector\FuncCall\RenameMktimeWithoutArgsToTimeRector;
use Rector\Php70\Rector\FunctionLike\ExceptionHandlerTypehintRector;
use Rector\Php70\Rector\If_\IfToSpaceshipRector;
use Rector\Php70\Rector\List_\EmptyListRector;
use Rector\Php70\Rector\MethodCall\ThisCallOnStaticMethodToStaticCallRector;
use Rector\Php70\Rector\StaticCall\StaticCallOnNonStaticToInstanceCallRector;
use Rector\Php70\Rector\Switch_\ReduceMultipleDefaultSwitchRector;
use Rector\Php70\Rector\Ternary\TernaryToSpaceshipRector;
use Rector\Php70\Rector\Variable\WrapVariableVariableNameInCurlyBracesRector;
use Rector\Php71\Rector\Assign\AssignArrayToStringRector;
use Rector\Php71\Rector\BinaryOp\BinaryOpBetweenNumberAndStringRector;
use Rector\Php71\Rector\BooleanOr\IsIterableRector;
use Rector\Php71\Rector\FuncCall\RemoveExtraParametersRector;
use Rector\Php71\Rector\List_\ListToArrayDestructRector;
use Rector\Php72\Rector\Assign\ListEachRector;
use Rector\Php72\Rector\Assign\ReplaceEachAssignmentWithKeyCurrentRector;
use Rector\Php72\Rector\FuncCall\CreateFunctionToAnonymousFunctionRector;
use Rector\Php72\Rector\FuncCall\GetClassOnNullRector;
use Rector\Php72\Rector\FuncCall\ParseStrWithResultArgumentRector;
use Rector\Php72\Rector\FuncCall\StringsAssertNakedRector;
use Rector\Php72\Rector\Unset_\UnsetCastRector;
use Rector\Php72\Rector\While_\WhileEachToForeachRector;
use Rector\Php73\Rector\BooleanOr\IsCountableRector;
use Rector\Php73\Rector\FuncCall\JsonThrowOnErrorRector;
use Rector\Php73\Rector\FuncCall\RegexDashEscapeRector;
use Rector\Php73\Rector\FuncCall\SetCookieRector;
use Rector\Php73\Rector\FuncCall\StringifyStrNeedlesRector;
use Rector\Php73\Rector\String_\SensitiveHereNowDocRector;
use Rector\Php74\Rector\ArrayDimFetch\CurlyToSquareBracketArrayStringRector;
use Rector\Php74\Rector\FuncCall\ArrayKeyExistsOnPropertyRector;
use Rector\Php74\Rector\FuncCall\FilterVarToAddSlashesRector;
use Rector\Php74\Rector\FuncCall\HebrevcToNl2brHebrevRector;
use Rector\Php74\Rector\FuncCall\MbStrrposEncodingArgumentPositionRector;
use Rector\Php74\Rector\FuncCall\MoneyFormatToNumberFormatRector;
use Rector\Php74\Rector\FuncCall\RestoreIncludePathToIniRestoreRector;
use Rector\Php74\Rector\LNumber\AddLiteralSeparatorToNumberRector;
use Rector\Php74\Rector\StaticCall\ExportToReflectionFunctionRector;
use Rector\Php74\Rector\Ternary\ParenthesizeNestedTernaryRector;
use Rector\Php80\Rector\Catch_\RemoveUnusedVariableInCatchRector;
use Rector\Php80\Rector\Class_\AnnotationToAttributeRector;
use Rector\Php80\Rector\Class_\ClassPropertyAssignToConstructorPromotionRector;
use Rector\Php80\Rector\Class_\StringableForToStringRector;
use Rector\Php80\Rector\ClassConstFetch\ClassOnThisVariableObjectRector;
use Rector\Php80\Rector\ClassMethod\FinalPrivateToPrivateVisibilityRector;
use Rector\Php80\Rector\ClassMethod\SetStateToStaticRector;
use Rector\Php80\Rector\FuncCall\ClassOnObjectRector;
use Rector\Php80\Rector\NotIdentical\MbStrContainsRector;
use Rector\Php80\Rector\Property\NestedAnnotationToAttributeRector;
use Rector\Php80\Rector\Ternary\GetDebugTypeRector;
use Rector\Php81\Rector\Array_\ArrayToFirstClassCallableRector;
use Rector\Php81\Rector\Array_\FirstClassCallableRector;
use Rector\Php81\Rector\Class_\MyCLabsClassToEnumRector;
use Rector\Php81\Rector\Class_\SpatieEnumClassToEnumRector;
use Rector\Php81\Rector\FuncCall\NullToStrictStringFuncCallArgRector;
use Rector\Php81\Rector\MethodCall\MyCLabsMethodCallToEnumConstRector;
use Rector\Php81\Rector\MethodCall\RemoveReflectionSetAccessibleCallsRector;
use Rector\Php81\Rector\MethodCall\SpatieEnumMethodCallToEnumConstRector;
use Rector\Php81\Rector\New_\MyCLabsConstructorCallToEnumFromRector;
use Rector\Php82\Rector\New_\FilesystemIteratorSkipDotsRector;
use Rector\Php82\Rector\Param\AddSensitiveParameterAttributeRector;
use Rector\Php83\Rector\BooleanAnd\JsonValidateRector;
use Rector\Php83\Rector\ClassMethod\AddOverrideAttributeToOverriddenMethodsRector;
use Rector\Php83\Rector\FuncCall\CombineHostPortLdapUriRector;
use Rector\Php83\Rector\FuncCall\DynamicClassConstFetchRector;
use Rector\Php83\Rector\FuncCall\RemoveGetClassGetParentClassNoArgsRector;
use Rector\Php84\Rector\Class_\DeprecatedAnnotationToDeprecatedAttributeRector;
use Rector\Php84\Rector\Foreach_\ForeachToArrayAllRector;
use Rector\Php84\Rector\Foreach_\ForeachToArrayAnyRector;
use Rector\Php84\Rector\Foreach_\ForeachToArrayFindKeyRector;
use Rector\Php84\Rector\Foreach_\ForeachToArrayFindRector;
use Rector\Php84\Rector\FuncCall\AddEscapeArgumentRector;
use Rector\Php84\Rector\FuncCall\RoundingModeEnumRector;
use Rector\Php85\Rector\ArrayDimFetch\ArrayFirstLastRector;
use Rector\Php85\Rector\Class_\SleepToSerializeRector;
use Rector\Php85\Rector\Class_\WakeupToUnserializeRector;
use Rector\Php85\Rector\ClassMethod\NullDebugInfoReturnRector;
use Rector\Php85\Rector\Const_\DeprecatedAnnotationToDeprecatedAttributeRector as Php85DeprecatedAnnotationToDeprecatedAttributeRector;
use Rector\Php85\Rector\Expression\NestedFuncCallsToPipeOperatorRector;
use Rector\Php85\Rector\FuncCall\ArrayKeyExistsNullToEmptyStringRector;
use Rector\Php85\Rector\FuncCall\ChrArgModuloRector;
use Rector\Php85\Rector\FuncCall\OrdSingleByteRector;
use Rector\Php85\Rector\FuncCall\RemoveFinfoBufferContextArgRector;
use Rector\Php85\Rector\StmtsAwareInterface\SequentialAssignmentsToPipeOperatorRector;
use Rector\Php85\Rector\Switch_\ColonAfterSwitchCaseRector;
use Rector\Privatization\Rector\MethodCall\PrivatizeLocalGetterToPropertyRector;
use Rector\Removing\Rector\Class_\RemoveInterfacesRector;
use Rector\Removing\Rector\Class_\RemoveTraitUseRector;
use Rector\Removing\Rector\ClassMethod\ArgumentRemoverRector;
use Rector\Removing\Rector\FuncCall\RemoveFuncCallArgRector;
use Rector\Removing\Rector\FuncCall\RemoveFuncCallRector;
use Rector\Renaming\Rector\Cast\RenameCastRector;
use Rector\Renaming\Rector\Class_\RenameAttributeRector;
use Rector\Renaming\Rector\ClassConstFetch\RenameClassConstFetchRector;
use Rector\Renaming\Rector\ClassMethod\RenameAnnotationRector;
use Rector\Renaming\Rector\ConstFetch\RenameConstantRector;
use Rector\Renaming\Rector\FuncCall\RenameFunctionRector;
use Rector\Renaming\Rector\MethodCall\RenameMethodRector;
use Rector\Renaming\Rector\Name\RenameClassRector;
use Rector\Renaming\Rector\PropertyFetch\RenamePropertyRector;
use Rector\Renaming\Rector\StaticCall\RenameStaticMethodRector;
use Rector\Renaming\Rector\String_\RenameStringRector;
use Rector\Strict\Rector\Empty_\DisallowedEmptyRuleFixerRector;
use Rector\Transform\Rector\ArrayDimFetch\ArrayDimFetchToMethodCallRector;
use Rector\Transform\Rector\Attribute\AttributeKeyToClassConstFetchRector;
use Rector\Transform\Rector\Class_\AddInterfaceByTraitRector;
use Rector\Transform\Rector\Class_\MergeInterfacesRector;
use Rector\Transform\Rector\ClassMethod\ReturnTypeWillChangeRector;
use Rector\Transform\Rector\ClassMethod\WrapReturnRector;
use Rector\Transform\Rector\ConstFetch\ConstFetchToClassConstFetchRector;
use Rector\Transform\Rector\FuncCall\FuncCallToConstFetchRector;
use Rector\Transform\Rector\FuncCall\FuncCallToMethodCallRector;
use Rector\Transform\Rector\FuncCall\FuncCallToNewRector;
use Rector\Transform\Rector\FuncCall\FuncCallToStaticCallRector;
use Rector\Transform\Rector\MethodCall\MethodCallToFuncCallRector;
use Rector\Transform\Rector\MethodCall\MethodCallToStaticCallRector;
use Rector\Transform\Rector\New_\NewToStaticCallRector;
use Rector\Transform\Rector\Scalar\ScalarValueToConstFetchRector;
use Rector\Transform\Rector\StaticCall\StaticCallToFuncCallRector;
use Rector\Transform\Rector\StaticCall\StaticCallToMethodCallRector;
use Rector\Transform\Rector\StaticCall\StaticCallToNewRector;
use Rector\Transform\Rector\String_\StringToClassConstantRector;
use Rector\TypeDeclaration\Rector\BooleanAnd\BinaryOpNullableToInstanceofRector;
use Rector\TypeDeclaration\Rector\Class_\ChildDoctrineRepositoryClassTypeRector;
use Rector\TypeDeclaration\Rector\Class_\MergeDateTimePropertyTypeDeclarationRector;
use Rector\TypeDeclaration\Rector\Class_\ObjectTypedPropertyFromJMSSerializerAttributeTypeRector;
use Rector\TypeDeclaration\Rector\Class_\ScalarTypedPropertyFromJMSSerializerAttributeTypeRector;
use Rector\TypeDeclaration\Rector\Class_\TypedPropertyFromCreateMockAssignRector;
use Rector\TypeDeclaration\Rector\Class_\TypedPropertyFromDocblockSetUpDefinedRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamArrayDocblockBasedOnCallableNativeFuncCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeDeclarationRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnArrayDocblockBasedOnArrayMapRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnDocblockForScalarArrayFromAssignsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeFromTryCatchTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\BoolReturnTypeFromBooleanConstReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\BoolReturnTypeFromBooleanStrictReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\NumericReturnTypeFromStrictReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromMockObjectRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictFluentReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromSymfonySerializerRector;
use Rector\TypeDeclaration\Rector\ClassMethod\StrictArrayParamDimFetchRector;
use Rector\TypeDeclaration\Rector\ClassMethod\StringReturnTypeFromStrictScalarReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\StringReturnTypeFromStrictStringReturnsRector;
use Rector\TypeDeclaration\Rector\Closure\AddClosureVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\Closure\ClosureReturnTypeRector;
use Rector\TypeDeclaration\Rector\Empty_\EmptyOnNullableObjectToInstanceOfRector;
use Rector\TypeDeclaration\Rector\FuncCall\AddArrayFunctionClosureParamTypeRector;
use Rector\TypeDeclaration\Rector\FuncCall\AddArrowFunctionParamArrayWhereDimFetchRector;
use Rector\TypeDeclaration\Rector\Function_\AddFunctionVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeForArrayMapRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeForArrayReduceRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeFromIterableMethodCallRector;
use Rector\TypeDeclaration\Rector\Property\AddPropertyTypeDeclarationRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromAssignsRector;
use Rector\TypeDeclaration\Rector\StmtsAwareInterface\DeclareStrictTypesRector;
use Rector\TypeDeclaration\Rector\StmtsAwareInterface\IncreaseDeclareStrictTypesRector;
use Rector\TypeDeclaration\Rector\While_\WhileNullableToInstanceofRector;
use Rector\TypeDeclarationDocblocks\Rector\Class_\AddReturnArrayDocblockFromDataProviderParamRector;
use Rector\Unambiguous\Rector\Class_\RemoveReturnThisFromSetterClassMethodRector;
use Rector\Visibility\Rector\ClassConst\ChangeConstantVisibilityRector;
use Rector\Visibility\Rector\ClassMethod\ChangeMethodVisibilityRector;
use Rector\Visibility\Rector\ClassMethod\ExplicitPublicClassMethodRector;

/**
 * List of ignored rules for example files checking
 * 
 * These rules will not be checked because:
 * - They are duplicate in rules.php
 * - They are experimental or deprecated
 * - They don't make sense for creating examples
 * - They are not available in current Rector version
 */
const IGNORED_RULES = [
    // Enable after PHP 8.5 support enabled
    SequentialAssignmentsToPipeOperatorRector::class,
    NestedFuncCallsToPipeOperatorRector::class,
    ObjectTypedPropertyFromJMSSerializerAttributeTypeRector::class,
    ScalarTypedPropertyFromJMSSerializerAttributeTypeRector::class,
    // Ignored rules
    ReplaceConstantBooleanNotRector::class,
    SleepToSerializeRector::class,
    WakeupToUnserializeRector::class,
    UnsetCastRector::class,
    ParseStrWithResultArgumentRector::class,
    GetClassOnNullRector::class,
    CreateFunctionToAnonymousFunctionRector::class,
    WhileEachToForeachRector::class,
    ListEachRector::class,
    ReplaceEachAssignmentWithKeyCurrentRector::class,
    NullToStrictStringFuncCallArgRector::class,
    MyCLabsConstructorCallToEnumFromRector::class,
    FirstClassCallableRector::class,
    SpatieEnumMethodCallToEnumConstRector::class,
    MyCLabsMethodCallToEnumConstRector::class,
    RemoveReflectionSetAccessibleCallsRector::class,
    MyCLabsClassToEnumRector::class,
    SpatieEnumClassToEnumRector::class,
    ParenthesizeNestedTernaryRector::class,
    MbStrrposEncodingArgumentPositionRector::class,
    ArrayKeyExistsOnPropertyRector::class,
    RestoreIncludePathToIniRestoreRector::class,
    FilterVarToAddSlashesRector::class,
    HebrevcToNl2brHebrevRector::class,
    MoneyFormatToNumberFormatRector::class,
    CurlyToSquareBracketArrayStringRector::class,
    AddLiteralSeparatorToNumberRector::class,
    ExportToReflectionFunctionRector::class,
    GetDebugTypeRector::class,
    ClassOnObjectRector::class,
    RemoveUnusedVariableInCatchRector::class,
    SetStateToStaticRector::class,
    FinalPrivateToPrivateVisibilityRector::class,
    NestedAnnotationToAttributeRector::class,
    ClassOnThisVariableObjectRector::class,
    MbStrContainsRector::class,
    StringableForToStringRector::class,
    AnnotationToAttributeRector::class,
    SensitiveHereNowDocRector::class,
    RegexDashEscapeRector::class,
    StringifyStrNeedlesRector::class,
    SetCookieRector::class,
    JsonThrowOnErrorRector::class,
    IsCountableRector::class,
    RenameStringRector::class,
    RenameFunctionRector::class,
    RenameAnnotationRector::class,
    RenameCastRector::class,
    RenameClassConstFetchRector::class,
    RenameConstantRector::class,
    RenamePropertyRector::class,
    RenameMethodRector::class,
    RenameStaticMethodRector::class,
    RenameClassRector::class,
    RenameAttributeRector::class,
    ReturnTypeFromMockObjectRector::class,
    AddParamTypeDeclarationRector::class,
    AddReturnArrayDocblockBasedOnArrayMapRector::class,
    BoolReturnTypeFromBooleanConstReturnsRector::class,
    StrictArrayParamDimFetchRector::class,
    StringReturnTypeFromStrictStringReturnsRector::class,
    ReturnTypeFromSymfonySerializerRector::class,
    BoolReturnTypeFromBooleanStrictReturnsRector::class,
    AddParamArrayDocblockBasedOnCallableNativeFuncCallRector::class,
    AddReturnTypeFromTryCatchTypeRector::class,
    StringReturnTypeFromStrictScalarReturnsRector::class,
    AddPropertyTypeDeclarationRector::class,
    TypedPropertyFromAssignsRector::class,
    EmptyOnNullableObjectToInstanceOfRector::class,
    WhileNullableToInstanceofRector::class,
    BinaryOpNullableToInstanceofRector::class,
    AddFunctionVoidReturnTypeWhereNoReturnRector::class,
    IncreaseDeclareStrictTypesRector::class,
    DeclareStrictTypesRector::class,
    TypedPropertyFromCreateMockAssignRector::class,
    TypedPropertyFromDocblockSetUpDefinedRector::class,
    MergeDateTimePropertyTypeDeclarationRector::class,
    ChildDoctrineRepositoryClassTypeRector::class,
    ChangeMethodVisibilityRector::class,
    ExplicitPublicClassMethodRector::class,
    ChangeConstantVisibilityRector::class,
    TimeFuncCallToCarbonRector::class,
    DateFuncCallToCarbonRector::class,
    DateTimeInstanceToCarbonRector::class,
    DateTimeMethodCallToCarbonRector::class,
    NewlineAfterStatementRector::class,
    RemoveUselessAliasInUseStatementRector::class,
    TernaryConditionVariableAssignmentRector::class,
    StaticClosureRector::class,
    SymplifyQuoteEscapeRector::class,
    UseClassKeywordForClassNameResolutionRector::class,
    CallUserFuncArrayToVariadicRector::class,
    FunctionFirstClassCallableRector::class,
    ClosureFromCallableToFirstClassCallableRector::class,
    CallUserFuncToMethodCallRector::class,
    CountArrayToEmptyArrayComparisonRector::class,
    StrictArraySearchRector::class,
    VersionCompareFuncCallToConstantRector::class,
    FunctionLikeToFirstClassCallableRector::class,
    CatchExceptionNameMatchingTypeRector::class,
    NewlineBeforeNewAssignSetRector::class,
    FuncGetArgsToVariadicParamRector::class,
    SplitGroupedPropertiesRector::class,
    EnumCaseToPascalCaseRector::class,
    NullableCompareToNullRector::class,
    SeparateMultiUseImportsRector::class,
    PostIncDecToPreIncDecRector::class,
    SplitDoubleAssignRector::class,
    WrapEncapsedVariableInCurlyBracesRector::class,
    SplitGroupedClassConstantsRector::class,
    RemoveFinalFromConstRector::class,
    ChangeNestedIfsToEarlyReturnRector::class,
    ChangeOrIfContinueToMultiContinueRector::class,
    ChangeNestedForeachIfsToEarlyContinueRector::class,
    PreparedValueToEarlyReturnRector::class,
    ReturnBinaryOrToEarlyReturnRector::class,
    PrivatizeLocalGetterToPropertyRector::class,
    PowToExpRector::class,
    UtilsJsonStaticCallNamedArgRector::class,
    AddAssertArrayFromClassMethodDocblockRector::class,
    AddSensitiveParameterAttributeRector::class,
    FilesystemIteratorSkipDotsRector::class,
    RemoveExtraParametersRector::class,
    ListToArrayDestructRector::class,
    IsIterableRector::class,
    BinaryOpBetweenNumberAndStringRector::class,
    AssignArrayToStringRector::class,
    RemoveFinfoBufferContextArgRector::class,
    ChrArgModuloRector::class,
    ArrayKeyExistsNullToEmptyStringRector::class,
    NullDebugInfoReturnRector::class,
    ArrayFirstLastRector::class,
    ColonAfterSwitchCaseRector::class,
    Php85DeprecatedAnnotationToDeprecatedAttributeRector::class,
    FlipNegatedTernaryInstanceofRector::class,
    AddEscapeArgumentRector::class,
    RoundingModeEnumRector::class,
    ForeachToArrayFindRector::class,
    ForeachToArrayFindKeyRector::class,
    ForeachToArrayAllRector::class,
    ForeachToArrayAnyRector::class,
    DeprecatedAnnotationToDeprecatedAttributeRector::class,
    BreakNotInLoopOrSwitchToReturnRector::class,
    TernaryToSpaceshipRector::class,
    MultiDirnameRector::class,
    CallUserMethodRector::class,
    RenameMktimeWithoutArgsToTimeRector::class,
    RandomFunctionRector::class,
    EregToPregMatchRector::class,
    ExceptionHandlerTypehintRector::class,
    Php4ConstructorRector::class,
    EmptyListRector::class,
    WrapVariableVariableNameInCurlyBracesRector::class,
    IfToSpaceshipRector::class,
    ListSplitStringRector::class,
    ListSwapArrayOrderRector::class,
    ThisCallOnStaticMethodToStaticCallRector::class,
    StaticCallOnNonStaticToInstanceCallRector::class,
    ReduceMultipleDefaultSwitchRector::class,
    RemoveConcatAutocastRector::class,
    RemoveFilterVarOnExactTypeRector::class,
    RemoveUnusedPublicMethodParameterRector::class,
    RemoveNullTagValueNodeRector::class,
    RemoveUselessAssignFromPropertyPromotionRector::class,
    RemoveArgumentFromDefaultParentCallRector::class,
    RemoveUselessReturnExprInConstructRector::class,
    RemoveNullPropertyInitializationRector::class,
    RemoveTypedPropertyNonMockDocblockRector::class,
    RemoveAnnotationRector::class,
    RemovePhpVersionIdCheckRector::class,
    RemoveDeadInstanceOfRector::class,
    RemoveAlwaysTrueIfConditionRector::class,
    RemoveTypedPropertyDeadInstanceOfRector::class,
    RemoveUnusedNonEmptyArrayBeforeForeachRector::class,
    SimplifyIfElseWithSameContentRector::class,
    UnwrapFutureCompatibleIfPhpVersionRector::class,
    RemoveUnusedForeachKeyRector::class,
    RemoveDeadContinueRector::class,
    RemoveDeadLoopRector::class,
    RemoveAndTrueRector::class,
    RemoveDuplicatedArrayKeyRector::class,
    RemoveDeadConditionAboveReturnRector::class,
    RemoveDeadStmtRector::class,
    SimplifyMirrorAssignRector::class,
    RemoveDuplicatedCaseInSwitchRector::class,
    ReplaceBlockToItsStmtsRector::class,
    RemoveDeadZeroAndOneOperationRector::class,
    DynamicClassConstFetchRector::class,
    CombineHostPortLdapUriRector::class,
    RemoveGetClassGetParentClassNoArgsRector::class,
    AddOverrideAttributeToOverriddenMethodsRector::class,
    JsonValidateRector::class,
    RenameParamToMatchTypeRector::class,
    RenameVariableToMatchNewTypeRector::class,
    RenameForeachValueVariableToMatchMethodCallReturnTypeRector::class,
    RenameForeachValueVariableToMatchExprVariableRector::class,
    RenameVariableToMatchMethodCallReturnTypeRector::class,
    DisallowedEmptyRuleFixerRector::class,
    TernaryImplodeToImplodeRector::class,
    NumberCompareToMaxFuncCallRector::class,
    CallUserFuncWithArrowFunctionToInlineRector::class,
    SingleInArrayToCompareRector::class,
    InlineIsAInstanceOfRector::class,
    SimplifyStrposLowerRector::class,
    SimplifyFuncGetArgsCountRector::class,
    IsAWithStringWithThirdArgumentRector::class,
    SetTypeToCastRector::class,
    ExplicitReturnNullRector::class,
    OptionalParametersAfterRequiredRector::class,
    SimplifyDeMorganBinaryRector::class,
    ReplaceMultipleBooleanNotRector::class,
    IssetOnPropertyObjectToPropertyExistsRector::class,
    AbsolutizeRequireAndIncludePathRector::class,
    CompleteMissingIfElseBracketRector::class,
    ExplicitBoolCompareRector::class,
    ForRepeatedCountToOwnVariableRector::class,
    SimplifyEmptyArrayCheckRector::class,
    RemoveUselessIsObjectCheckRector::class,
    NewStaticToNewSelfRector::class,
    UseIdenticalOverEqualWithSameTypeRector::class,
    SimplifyBoolIdenticalTrueRector::class,
    FlipTypeControlToUseExclusiveTypeRector::class,
    StrlenZeroToIdenticalEmptyStringRector::class,
    SimplifyArraySearchRector::class,
    SimplifyConditionsRector::class,
    BooleanNotIdenticalToNotIdenticalRector::class,
    SingularSwitchToIfRector::class,
    DynamicDocBlockPropertyToNativePropertyRector::class,
    ConvertStaticToSelfRector::class,
    RemoveReadonlyPropertyVisibilityOnReadonlyClassRector::class,
    RemoveFuncCallArgRector::class,
    RemoveFuncCallRector::class,
    ArgumentRemoverRector::class,
    RemoveInterfacesRector::class,
    RemoveTraitUseRector::class,
    StringClassNameToClassConstantRector::class,
    GetCalledClassToStaticClassRector::class,
    GetCalledClassToSelfClassRector::class,
    PregReplaceEModifierRector::class,
    StaticToSelfOnFinalClassRector::class,
    ClassConstantToSelfClassRector::class,
    VarToPublicPropertyRector::class,
    ContinueToBreakInSwitchRector::class,
    StringToClassConstantRector::class,
    FuncCallToMethodCallRector::class,
    FuncCallToNewRector::class,
    FuncCallToStaticCallRector::class,
    FuncCallToConstFetchRector::class,
    AttributeKeyToClassConstFetchRector::class,
    ReturnTypeWillChangeRector::class,
    WrapReturnRector::class,
    ConstFetchToClassConstFetchRector::class,
    ArrayDimFetchToMethodCallRector::class,
    NewToStaticCallRector::class,
    MethodCallToStaticCallRector::class,
    MethodCallToFuncCallRector::class,
    StaticCallToNewRector::class,
    StaticCallToFuncCallRector::class,
    StaticCallToMethodCallRector::class,
    ScalarValueToConstFetchRector::class,
    MergeInterfacesRector::class,
    AddInterfaceByTraitRector::class,
    FunctionArgumentDefaultValueReplacerRector::class,
    ArgumentAdderRector::class,
    ReplaceArgumentDefaultValueRector::class,
    RemoveMethodCallParamRector::class,
    DirNameFileConstantToDirConstantRector::class,
    ReplaceHttpServerVarsByServerRector::class,
    RemoveZeroBreakContinueRector::class,
    RemoveReferenceFromCallRector::class,
    OrdSingleByteRector::class,
    StaticArrowFunctionRector::class,
    AddReturnArrayDocblockFromDataProviderParamRector::class,
    RemoveReturnThisFromSetterClassMethodRector::class,
    ArrowFunctionDelegatingCallToFirstClassCallableRector::class,
    ClosureDelegatingCallToFirstClassCallableRector::class,
    ArrayToFirstClassCallableRector::class,
    SortNamedParamRector::class,
];