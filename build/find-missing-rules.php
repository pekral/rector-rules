<?php

declare(strict_types = 1);

require_once __DIR__ . '/../vendor/autoload.php';

use Rector\Rector\AbstractRector;

/**
 * List of Rector rules that should be ignored (not defined in rules/rules.php)
 */
const IGNORED_RULES = [
    'Rector\Php72\Rector\Unset_\UnsetCastRector',
    'Rector\Php72\Rector\FuncCall\ParseStrWithResultArgumentRector',
    'Rector\Php72\Rector\FuncCall\GetClassOnNullRector',
    'Rector\Php72\Rector\FuncCall\StringsAssertNakedRector',
    'Rector\Php72\Rector\FuncCall\CreateFunctionToAnonymousFunctionRector',
    'Rector\Php72\Rector\While_\WhileEachToForeachRector',
    'Rector\Php72\Rector\Assign\ListEachRector',
    'Rector\Php72\Rector\Assign\ReplaceEachAssignmentWithKeyCurrentRector',
    'Rector\Php81\Rector\FuncCall\NullToStrictStringFuncCallArgRector',
    'Rector\Php81\Rector\New_\MyCLabsConstructorCallToEnumFromRector',
    'Rector\Php81\Rector\Array_\FirstClassCallableRector',
    'Rector\Php81\Rector\MethodCall\SpatieEnumMethodCallToEnumConstRector',
    'Rector\Php81\Rector\MethodCall\MyCLabsMethodCallToEnumConstRector',
    'Rector\Php81\Rector\MethodCall\RemoveReflectionSetAccessibleCallsRector',
    'Rector\Php81\Rector\Class_\MyCLabsClassToEnumRector',
    'Rector\Php81\Rector\Class_\SpatieEnumClassToEnumRector',
    'Rector\Php74\Rector\Ternary\ParenthesizeNestedTernaryRector',
    'Rector\Php74\Rector\FuncCall\MbStrrposEncodingArgumentPositionRector',
    'Rector\Php74\Rector\FuncCall\ArrayKeyExistsOnPropertyRector',
    'Rector\Php74\Rector\FuncCall\RestoreIncludePathToIniRestoreRector',
    'Rector\Php74\Rector\FuncCall\FilterVarToAddSlashesRector',
    'Rector\Php74\Rector\FuncCall\HebrevcToNl2brHebrevRector',
    'Rector\Php74\Rector\FuncCall\MoneyFormatToNumberFormatRector',
    'Rector\Php74\Rector\ArrayDimFetch\CurlyToSquareBracketArrayStringRector',
    'Rector\Php74\Rector\LNumber\AddLiteralSeparatorToNumberRector',
    'Rector\Php74\Rector\Double\RealToFloatTypeCastRector',
    'Rector\Php74\Rector\StaticCall\ExportToReflectionFunctionRector',
    'Rector\Php80\Rector\Ternary\GetDebugTypeRector',
    'Rector\Php80\Rector\FuncCall\ClassOnObjectRector',
    'Rector\Php80\Rector\Catch_\RemoveUnusedVariableInCatchRector',
    'Rector\Php80\Rector\ClassMethod\SetStateToStaticRector',
    'Rector\Php80\Rector\ClassMethod\FinalPrivateToPrivateVisibilityRector',
    'Rector\Php80\Rector\Property\NestedAnnotationToAttributeRector',
    'Rector\Php80\Rector\ClassConstFetch\ClassOnThisVariableObjectRector',
    'Rector\Php80\Rector\NotIdentical\MbStrContainsRector',
    'Rector\Php80\Rector\Class_\StringableForToStringRector',
    'Rector\Php80\Rector\Class_\AnnotationToAttributeRector',
    'Rector\Php80\Rector\Class_\ClassPropertyAssignToConstructorPromotionRector',
    'Rector\Php73\Rector\String_\SensitiveHereNowDocRector',
    'Rector\Php73\Rector\FuncCall\RegexDashEscapeRector',
    'Rector\Php73\Rector\FuncCall\StringifyStrNeedlesRector',
    'Rector\Php73\Rector\FuncCall\SetCookieRector',
    'Rector\Php73\Rector\FuncCall\JsonThrowOnErrorRector',
    'Rector\Php73\Rector\BooleanOr\IsCountableRector',
    'Rector\Renaming\Rector\String_\RenameStringRector',
    'Rector\Renaming\Rector\FuncCall\RenameFunctionRector',
    'Rector\Renaming\Rector\FunctionLike\RenameFunctionLikeParamWithinCallLikeArgRector',
    'Rector\Renaming\Rector\ClassMethod\RenameAnnotationRector',
    'Rector\Renaming\Rector\Cast\RenameCastRector',
    'Rector\Renaming\Rector\ClassConstFetch\RenameClassConstFetchRector',
    'Rector\Renaming\Rector\ConstFetch\RenameConstantRector',
    'Rector\Renaming\Rector\PropertyFetch\RenamePropertyRector',
    'Rector\Renaming\Rector\MethodCall\RenameMethodRector',
    'Rector\Renaming\Rector\StaticCall\RenameStaticMethodRector',
    'Rector\Renaming\Rector\Name\RenameClassRector',
    'Rector\Renaming\Rector\Class_\RenameAttributeRector',
    'Rector\TypeDeclaration\Rector\Closure\ClosureReturnTypeRector',
    'Rector\TypeDeclaration\Rector\Closure\AddClosureVoidReturnTypeWhereNoReturnRector',
    'Rector\TypeDeclaration\Rector\FuncCall\AddArrowFunctionParamArrayWhereDimFetchRector',
    'Rector\TypeDeclaration\Rector\FuncCall\AddArrayFunctionClosureParamTypeRector',
    'Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeForArrayMapRector',
    'Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeFromArgRector',
    'Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeFromIterableMethodCallRector',
    'Rector\TypeDeclaration\Rector\FunctionLike\AddParamTypeForFunctionLikeWithinCallLikeArgDeclarationRector',
    'Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeForArrayReduceRector',
    'Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeFromObjectRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromMockObjectRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\NumericReturnTypeFromStrictReturnsRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictFluentReturnRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeDeclarationRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddReturnDocblockForScalarArrayFromAssignsRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddReturnArrayDocblockBasedOnArrayMapRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\BoolReturnTypeFromBooleanConstReturnsRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\StrictArrayParamDimFetchRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\StringReturnTypeFromStrictStringReturnsRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromSymfonySerializerRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddTypeFromResourceDocblockRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\BoolReturnTypeFromBooleanStrictReturnsRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddParamArrayDocblockBasedOnCallableNativeFuncCallRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeFromTryCatchTypeRector',
    'Rector\TypeDeclaration\Rector\ClassMethod\StringReturnTypeFromStrictScalarReturnsRector',
    'Rector\TypeDeclaration\Rector\Property\AddPropertyTypeDeclarationRector',
    'Rector\TypeDeclaration\Rector\Property\TypedPropertyFromAssignsRector',
    'Rector\TypeDeclaration\Rector\Empty_\EmptyOnNullableObjectToInstanceOfRector',
    'Rector\TypeDeclaration\Rector\While_\WhileNullableToInstanceofRector',
    'Rector\TypeDeclaration\Rector\BooleanAnd\BinaryOpNullableToInstanceofRector',
    'Rector\TypeDeclaration\Rector\Function_\AddFunctionVoidReturnTypeWhereNoReturnRector',
    'Rector\TypeDeclaration\Rector\Expression\InlineVarDocTagToAssertRector',
    'Rector\TypeDeclaration\Rector\StmtsAwareInterface\IncreaseDeclareStrictTypesRector',
    'Rector\TypeDeclaration\Rector\StmtsAwareInterface\DeclareStrictTypesRector',
    'Rector\TypeDeclaration\Rector\Class_\TypedPropertyFromCreateMockAssignRector',
    'Rector\TypeDeclaration\Rector\Class_\TypedPropertyFromJMSSerializerAttributeTypeRector',
    'Rector\TypeDeclaration\Rector\Class_\TypedPropertyFromDocblockSetUpDefinedRector',
    'Rector\TypeDeclaration\Rector\Class_\MergeDateTimePropertyTypeDeclarationRector',
    'Rector\TypeDeclaration\Rector\Class_\ChildDoctrineRepositoryClassTypeRector',
    'Rector\Visibility\Rector\ClassMethod\ChangeMethodVisibilityRector',
    'Rector\Visibility\Rector\ClassMethod\ExplicitPublicClassMethodRector',
    'Rector\Visibility\Rector\ClassConst\ChangeConstantVisibilityRector',
    'Rector\Carbon\Rector\FuncCall\TimeFuncCallToCarbonRector',
    'Rector\Carbon\Rector\FuncCall\DateFuncCallToCarbonRector',
    'Rector\Carbon\Rector\New_\DateTimeInstanceToCarbonRector',
    'Rector\Carbon\Rector\MethodCall\DateTimeMethodCallToCarbonRector',
    'Rector\CodingStyle\Rector\Stmt\NewlineAfterStatementRector',
    'Rector\CodingStyle\Rector\Stmt\RemoveUselessAliasInUseStatementRector',
    'Rector\CodingStyle\Rector\Ternary\TernaryConditionVariableAssignmentRector',
    'Rector\CodingStyle\Rector\Closure\StaticClosureRector',
    'Rector\CodingStyle\Rector\String_\SymplifyQuoteEscapeRector',
    'Rector\CodingStyle\Rector\String_\UseClassKeywordForClassNameResolutionRector',
    'Rector\CodingStyle\Rector\FuncCall\CallUserFuncArrayToVariadicRector',
    'Rector\CodingStyle\Rector\FuncCall\FunctionFirstClassCallableRector',
    'Rector\CodingStyle\Rector\FuncCall\ClosureFromCallableToFirstClassCallableRector',
    'Rector\CodingStyle\Rector\FuncCall\CallUserFuncToMethodCallRector',
    'Rector\CodingStyle\Rector\FuncCall\CountArrayToEmptyArrayComparisonRector',
    'Rector\CodingStyle\Rector\FuncCall\StrictArraySearchRector',
    'Rector\CodingStyle\Rector\FuncCall\VersionCompareFuncCallToConstantRector',
    'Rector\CodingStyle\Rector\FunctionLike\FunctionLikeToFirstClassCallableRector',
    'Rector\CodingStyle\Rector\Catch_\CatchExceptionNameMatchingTypeRector',
    'Rector\CodingStyle\Rector\ClassMethod\NewlineBeforeNewAssignSetRector',
    'Rector\CodingStyle\Rector\ClassMethod\FuncGetArgsToVariadicParamRector',
    'Rector\CodingStyle\Rector\Property\SplitGroupedPropertiesRector',
    'Rector\CodingStyle\Rector\Enum_\EnumCaseToPascalCaseRector',
    'Rector\CodingStyle\Rector\If_\NullableCompareToNullRector',
    'Rector\CodingStyle\Rector\Use_\SeparateMultiUseImportsRector',
    'Rector\CodingStyle\Rector\Foreach_\MultiDimensionalArrayToArrayDestructRector',
    'Rector\CodingStyle\Rector\PostInc\PostIncDecToPreIncDecRector',
    'Rector\CodingStyle\Rector\Assign\SplitDoubleAssignRector',
    'Rector\CodingStyle\Rector\Encapsed\WrapEncapsedVariableInCurlyBracesRector',
    'Rector\CodingStyle\Rector\ClassConst\SplitGroupedClassConstantsRector',
    'Rector\CodingStyle\Rector\ClassConst\RemoveFinalFromConstRector',
    'Rector\EarlyReturn\Rector\If_\ChangeNestedIfsToEarlyReturnRector',
    'Rector\EarlyReturn\Rector\If_\ChangeOrIfContinueToMultiContinueRector',
    'Rector\EarlyReturn\Rector\Foreach_\ChangeNestedForeachIfsToEarlyContinueRector',
    'Rector\EarlyReturn\Rector\Return_\PreparedValueToEarlyReturnRector',
    'Rector\EarlyReturn\Rector\Return_\ReturnBinaryOrToEarlyReturnRector',
    'Rector\Privatization\Rector\MethodCall\PrivatizeLocalGetterToPropertyRector',
    'Rector\Php56\Rector\FuncCall\PowToExpRector',
    'Rector\NetteUtils\Rector\StaticCall\UtilsJsonStaticCallNamedArgRector',
    'Rector\Assert\Rector\ClassMethod\AddAssertArrayFromClassMethodDocblockRector',
    'Rector\Php82\Rector\Param\AddSensitiveParameterAttributeRector',
    'Rector\Php82\Rector\New_\FilesystemIteratorSkipDotsRector',
    'Rector\Php71\Rector\FuncCall\RemoveExtraParametersRector',
    'Rector\Php71\Rector\List_\ListToArrayDestructRector',
    'Rector\Php71\Rector\BooleanOr\IsIterableRector',
    'Rector\Php71\Rector\BinaryOp\BinaryOpBetweenNumberAndStringRector',
    'Rector\Php71\Rector\Assign\AssignArrayToStringRector',
    'Rector\Php85\Rector\FuncCall\RemoveFinfoBufferContextArgRector',
    'Rector\Php85\Rector\FuncCall\ChrArgModuloRector',
    'Rector\Php85\Rector\FuncCall\ArrayKeyExistsNullToEmptyStringRector',
    'Rector\Php85\Rector\ClassMethod\NullDebugInfoReturnRector',
    'Rector\Php85\Rector\ArrayDimFetch\ArrayFirstLastRector',
    'Rector\Php85\Rector\Switch_\ColonAfterSwitchCaseRector',
    'Rector\Php85\Rector\Const_\DeprecatedAnnotationToDeprecatedAttributeRector',
    'Rector\Instanceof_\Rector\Ternary\FlipNegatedTernaryInstanceofRector',
    'Rector\Php84\Rector\FuncCall\AddEscapeArgumentRector',
    'Rector\Php84\Rector\FuncCall\RoundingModeEnumRector',
    'Rector\Php84\Rector\Foreach_\ForeachToArrayFindRector',
    'Rector\Php84\Rector\Foreach_\ForeachToArrayFindKeyRector',
    'Rector\Php84\Rector\Foreach_\ForeachToArrayAllRector',
    'Rector\Php84\Rector\Foreach_\ForeachToArrayAnyRector',
    'Rector\Php84\Rector\Class_\DeprecatedAnnotationToDeprecatedAttributeRector',
    'Rector\Php70\Rector\Break_\BreakNotInLoopOrSwitchToReturnRector',
    'Rector\Php70\Rector\Ternary\TernaryToSpaceshipRector',
    'Rector\Php70\Rector\FuncCall\MultiDirnameRector',
    'Rector\Php70\Rector\FuncCall\CallUserMethodRector',
    'Rector\Php70\Rector\FuncCall\RenameMktimeWithoutArgsToTimeRector',
    'Rector\Php70\Rector\FuncCall\RandomFunctionRector',
    'Rector\Php70\Rector\FuncCall\EregToPregMatchRector',
    'Rector\Php70\Rector\FunctionLike\ExceptionHandlerTypehintRector',
    'Rector\Php70\Rector\ClassMethod\Php4ConstructorRector',
    'Rector\Php70\Rector\List_\EmptyListRector',
    'Rector\Php70\Rector\Variable\WrapVariableVariableNameInCurlyBracesRector',
    'Rector\Php70\Rector\If_\IfToSpaceshipRector',
    'Rector\Php70\Rector\Assign\ListSplitStringRector',
    'Rector\Php70\Rector\Assign\ListSwapArrayOrderRector',
    'Rector\Php70\Rector\MethodCall\ThisCallOnStaticMethodToStaticCallRector',
    'Rector\Php70\Rector\StaticCall\StaticCallOnNonStaticToInstanceCallRector',
    'Rector\Php70\Rector\Switch_\ReduceMultipleDefaultSwitchRector',
    'Rector\DeadCode\Rector\Concat\RemoveConcatAutocastRector',
    'Rector\DeadCode\Rector\FuncCall\RemoveFilterVarOnExactTypeRector',
    'Rector\DeadCode\Rector\FunctionLike\NarrowTooWideReturnTypeRector',
    'Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPublicMethodParameterRector',
    'Rector\DeadCode\Rector\ClassMethod\RemoveNullTagValueNodeRector',
    'Rector\DeadCode\Rector\ClassMethod\RemoveUselessAssignFromPropertyPromotionRector',
    'Rector\DeadCode\Rector\ClassMethod\RemoveArgumentFromDefaultParentCallRector',
    'Rector\DeadCode\Rector\ClassMethod\RemoveUselessReturnExprInConstructRector',
    'Rector\DeadCode\Rector\PropertyProperty\RemoveNullPropertyInitializationRector',
    'Rector\DeadCode\Rector\Property\RemoveUnusedPrivatePropertyRector',
    'Rector\DeadCode\Rector\ClassLike\RemoveTypedPropertyNonMockDocblockRector',
    'Rector\DeadCode\Rector\ClassLike\RemoveAnnotationRector',
    'Rector\DeadCode\Rector\ConstFetch\RemovePhpVersionIdCheckRector',
    'Rector\DeadCode\Rector\If_\RemoveDeadInstanceOfRector',
    'Rector\DeadCode\Rector\If_\RemoveAlwaysTrueIfConditionRector',
    'Rector\DeadCode\Rector\If_\RemoveTypedPropertyDeadInstanceOfRector',
    'Rector\DeadCode\Rector\If_\RemoveUnusedNonEmptyArrayBeforeForeachRector',
    'Rector\DeadCode\Rector\If_\SimplifyIfElseWithSameContentRector',
    'Rector\DeadCode\Rector\If_\UnwrapFutureCompatibleIfPhpVersionRector',
    'Rector\DeadCode\Rector\Foreach_\RemoveUnusedForeachKeyRector',
    'Rector\DeadCode\Rector\For_\RemoveDeadContinueRector',
    'Rector\DeadCode\Rector\For_\RemoveDeadLoopRector',
    'Rector\DeadCode\Rector\BooleanAnd\RemoveAndTrueRector',
    'Rector\DeadCode\Rector\Array_\RemoveDuplicatedArrayKeyRector',
    'Rector\DeadCode\Rector\Return_\RemoveDeadConditionAboveReturnRector',
    'Rector\DeadCode\Rector\Expression\RemoveDeadStmtRector',
    'Rector\DeadCode\Rector\Expression\SimplifyMirrorAssignRector',
    'Rector\DeadCode\Rector\Switch_\RemoveDuplicatedCaseInSwitchRector',
    'Rector\DeadCode\Rector\Block\ReplaceBlockToItsStmtsRector',
    'Rector\DeadCode\Rector\Plus\RemoveDeadZeroAndOneOperationRector',
    'Rector\Php83\Rector\FuncCall\DynamicClassConstFetchRector',
    'Rector\Php83\Rector\FuncCall\CombineHostPortLdapUriRector',
    'Rector\Php83\Rector\FuncCall\RemoveGetClassGetParentClassNoArgsRector',
    'Rector\Php83\Rector\ClassMethod\AddOverrideAttributeToOverriddenMethodsRector',
    'Rector\Php83\Rector\BooleanAnd\JsonValidateRector',
    'Rector\Naming\Rector\ClassMethod\RenameParamToMatchTypeRector',
    'Rector\Naming\Rector\ClassMethod\RenameVariableToMatchNewTypeRector',
    'Rector\Naming\Rector\Foreach_\RenameForeachValueVariableToMatchMethodCallReturnTypeRector',
    'Rector\Naming\Rector\Foreach_\RenameForeachValueVariableToMatchExprVariableRector',
    'Rector\Naming\Rector\Assign\RenameVariableToMatchMethodCallReturnTypeRector',
    'Rector\Strict\Rector\Ternary\DisallowedShortTernaryRuleFixerRector',
    'Rector\Strict\Rector\Ternary\BooleanInTernaryOperatorRuleFixerRector',
    'Rector\Strict\Rector\BooleanNot\BooleanInBooleanNotRuleFixerRector',
    'Rector\Strict\Rector\Empty_\DisallowedEmptyRuleFixerRector',
    'Rector\Strict\Rector\If_\BooleanInIfConditionRuleFixerRector',
    'Rector\CodeQuality\Rector\Ternary\TernaryImplodeToImplodeRector',
    'Rector\CodeQuality\Rector\Ternary\NumberCompareToMaxFuncCallRector',
    'Rector\CodeQuality\Rector\FuncCall\CallUserFuncWithArrowFunctionToInlineRector',
    'Rector\CodeQuality\Rector\FuncCall\SingleInArrayToCompareRector',
    'Rector\CodeQuality\Rector\FuncCall\InlineIsAInstanceOfRector',
    'Rector\CodeQuality\Rector\FuncCall\SimplifyStrposLowerRector',
    'Rector\CodeQuality\Rector\FuncCall\SimplifyFuncGetArgsCountRector',
    'Rector\CodeQuality\Rector\FuncCall\IsAWithStringWithThirdArgumentRector',
    'Rector\CodeQuality\Rector\FuncCall\SetTypeToCastRector',
    'Rector\CodeQuality\Rector\ClassMethod\ExplicitReturnNullRector',
    'Rector\CodeQuality\Rector\ClassMethod\OptionalParametersAfterRequiredRector',
    'Rector\CodeQuality\Rector\BooleanNot\SimplifyDeMorganBinaryRector',
    'Rector\CodeQuality\Rector\BooleanNot\ReplaceMultipleBooleanNotRector',
    'Rector\CodeQuality\Rector\Isset_\IssetOnPropertyObjectToPropertyExistsRector',
    'Rector\CodeQuality\Rector\Include_\AbsolutizeRequireAndIncludePathRector',
    'Rector\CodeQuality\Rector\If_\CompleteMissingIfElseBracketRector',
    'Rector\CodeQuality\Rector\If_\ExplicitBoolCompareRector',
    'Rector\CodeQuality\Rector\For_\ForRepeatedCountToOwnVariableRector',
    'Rector\CodeQuality\Rector\BooleanAnd\SimplifyEmptyArrayCheckRector',
    'Rector\CodeQuality\Rector\BooleanAnd\RemoveUselessIsObjectCheckRector',
    'Rector\CodeQuality\Rector\New_\NewStaticToNewSelfRector',
    'Rector\CodeQuality\Rector\Equal\UseIdenticalOverEqualWithSameTypeRector',
    'Rector\CodeQuality\Rector\Identical\SimplifyBoolIdenticalTrueRector',
    'Rector\CodeQuality\Rector\Identical\FlipTypeControlToUseExclusiveTypeRector',
    'Rector\CodeQuality\Rector\Identical\StrlenZeroToIdenticalEmptyStringRector',
    'Rector\CodeQuality\Rector\Identical\SimplifyArraySearchRector',
    'Rector\CodeQuality\Rector\Identical\SimplifyConditionsRector',
    'Rector\CodeQuality\Rector\Identical\BooleanNotIdenticalToNotIdenticalRector',
    'Rector\CodeQuality\Rector\Switch_\SingularSwitchToIfRector',
    'Rector\CodeQuality\Rector\Class_\DynamicDocBlockPropertyToNativePropertyRector',
    'Rector\CodeQuality\Rector\Class_\ConvertStaticToSelfRector',
    'Rector\CodeQuality\Rector\Class_\RemoveReadonlyPropertyVisibilityOnReadonlyClassRector',
    'Rector\Removing\Rector\FuncCall\RemoveFuncCallArgRector',
    'Rector\Removing\Rector\FuncCall\RemoveFuncCallRector',
    'Rector\Removing\Rector\ClassMethod\ArgumentRemoverRector',
    'Rector\Removing\Rector\Class_\RemoveInterfacesRector',
    'Rector\Removing\Rector\Class_\RemoveTraitUseRector',
    'Rector\Php55\Rector\String_\StringClassNameToClassConstantRector',
    'Rector\Php55\Rector\FuncCall\GetCalledClassToStaticClassRector',
    'Rector\Php55\Rector\FuncCall\GetCalledClassToSelfClassRector',
    'Rector\Php55\Rector\FuncCall\PregReplaceEModifierRector',
    'Rector\Php55\Rector\ClassConstFetch\StaticToSelfOnFinalClassRector',
    'Rector\Php55\Rector\Class_\ClassConstantToSelfClassRector',
    'Rector\Php52\Rector\Property\VarToPublicPropertyRector',
    'Rector\Php52\Rector\Switch_\ContinueToBreakInSwitchRector',
    'Rector\Transform\Rector\String_\StringToClassConstantRector',
    'Rector\Transform\Rector\FuncCall\WrapFuncCallWithPhpVersionIdCheckerRector',
    'Rector\Transform\Rector\FuncCall\FuncCallToMethodCallRector',
    'Rector\Transform\Rector\FuncCall\FuncCallToNewRector',
    'Rector\Transform\Rector\FuncCall\FuncCallToStaticCallRector',
    'Rector\Transform\Rector\FuncCall\FuncCallToConstFetchRector',
    'Rector\Transform\Rector\Attribute\AttributeKeyToClassConstFetchRector',
    'Rector\Transform\Rector\ClassMethod\ReturnTypeWillChangeRector',
    'Rector\Transform\Rector\ClassMethod\WrapReturnRector',
    'Rector\Transform\Rector\ConstFetch\ConstFetchToClassConstFetchRector',
    'Rector\Transform\Rector\ArrayDimFetch\ArrayDimFetchToMethodCallRector',
    'Rector\Transform\Rector\New_\NewToStaticCallRector',
    'Rector\Transform\Rector\Assign\PropertyFetchToMethodCallRector',
    'Rector\Transform\Rector\Assign\PropertyAssignToMethodCallRector',
    'Rector\Transform\Rector\MethodCall\MethodCallToStaticCallRector',
    'Rector\Transform\Rector\MethodCall\ReplaceParentCallByPropertyCallRector',
    'Rector\Transform\Rector\MethodCall\MethodCallToFuncCallRector',
    'Rector\Transform\Rector\MethodCall\MethodCallToNewRector',
    'Rector\Transform\Rector\MethodCall\MethodCallToPropertyFetchRector',
    'Rector\Transform\Rector\StaticCall\StaticCallToNewRector',
    'Rector\Transform\Rector\StaticCall\StaticCallToFuncCallRector',
    'Rector\Transform\Rector\StaticCall\StaticCallToMethodCallRector',
    'Rector\Transform\Rector\Scalar\ScalarValueToConstFetchRector',
    'Rector\Transform\Rector\Class_\MergeInterfacesRector',
    'Rector\Transform\Rector\Class_\AddAllowDynamicPropertiesAttributeRector',
    'Rector\Transform\Rector\Class_\AddInterfaceByTraitRector',
    'Rector\Transform\Rector\Class_\ParentClassToTraitsRector',
    'Rector\Arguments\Rector\FuncCall\FunctionArgumentDefaultValueReplacerRector',
    'Rector\Arguments\Rector\ClassMethod\ArgumentAdderRector',
    'Rector\Arguments\Rector\ClassMethod\ReplaceArgumentDefaultValueRector',
    'Rector\Arguments\Rector\MethodCall\RemoveMethodCallParamRector',
    'Rector\Php53\Rector\FuncCall\DirNameFileConstantToDirConstantRector',
    'Rector\Php53\Rector\Variable\ReplaceHttpServerVarsByServerRector',
    'Rector\Php54\Rector\Break_\RemoveZeroBreakContinueRector',
    'Rector\Php54\Rector\FuncCall\RemoveReferenceFromCallRector',
    'Rector\Php54\Rector\Array_\LongArrayToShortArrayRector',
];

/**
 * Load all Rector rules from vendor
 */
function getAllRectorRules(): array
{
    $rules = [];
    
    // Search vendor/rector/rector/rules directory
    $rectorPath = __DIR__ . '/../vendor/rector/rector/rules';
    
    if (!is_dir($rectorPath)) {
        echo "Error: Directory vendor/rector/rector/rules does not exist.\n";

        return $rules;
    }
    
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($rectorPath),
    );
    
    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $className = buildClassNameFromFile($file, $rectorPath);
            
            if (isValidRectorRule($className)) {
                $rules[] = $className;
            }
        }
    }
    
    return $rules;
}

/**
 * Build class name from file path
 */
function buildClassNameFromFile(SplFileInfo $file, string $rectorPath): string
{
    $relativePath = str_replace($rectorPath . '/', '', $file->getPathname());
    $className = str_replace('/', '\\', $relativePath);
    
    return 'Rector\\' . str_replace('.php', '', $className);
}

/**
 * Check if class is a valid Rector rule
 */
function isValidRectorRule(string $className): bool
{
    if (!class_exists($className)) {
        return false;
    }
    
    $reflection = new ReflectionClass($className);

    return $reflection->isSubclassOf(AbstractRector::class) && !$reflection->isAbstract();
}

/**
 * Load defined rules from rules/rules.php
 */
function getDefinedRules(): array
{
    $rulesFile = __DIR__ . '/../rules/rules.php';
    
    if (!file_exists($rulesFile)) {
        echo "Error: File rules/rules.php does not exist.\n";

        return [];
    }
    
    $content = file_get_contents($rulesFile);
    
    return extractUseStatements($content);
}

/**
 * Extract use statements from file content
 */
function extractUseStatements(string $content): array
{
    $definedRules = [];
    
    // Find all use statements
    preg_match_all('/use\s+([^;]+);/', $content, $matches);
    
    foreach ($matches[1] as $useStatement) {
        $definedRules[] = trim($useStatement);
    }
    
    return $definedRules;
}

/**
 * Main function
 */
function main(): void
{
    $allRules = loadAndDisplayAllRules();
    $definedRules = loadAndDisplayDefinedRules();
    
    $missingRules = findMissingRules($allRules, $definedRules);
    
    if ($missingRules === []) {
        echo "✅ All available Rector rules are already defined in rules/rules.php\n";

        return;
    }
    
    displayMissingRules($missingRules);
    exit(1);
}

/**
 * Load and display all Rector rules
 */
function loadAndDisplayAllRules(): array
{
    echo "Loading all Rector rules from vendor...\n";
    $allRules = getAllRectorRules();
    echo "Found " . count($allRules) . " Rector rules.\n\n";
    
    return $allRules;
}

/**
 * Load and display defined rules
 */
function loadAndDisplayDefinedRules(): array
{
    echo "Loading defined rules from rules/rules.php...\n";
    $definedRules = getDefinedRules();
    echo "Found " . count($definedRules) . " defined rules.\n\n";
    
    return $definedRules;
}

/**
 * Find missing rules
 */
function findMissingRules(array $allRules, array $definedRules): array
{
    return array_diff($allRules, $definedRules, IGNORED_RULES);
}

/**
 * Display missing rules
 */
function displayMissingRules(array $missingRules): void
{
    echo "❌ Found " . count($missingRules) . " Rector rules that are not defined:\n\n";
    
    $categorizedRules = categorizeRules($missingRules);
    
    foreach ($categorizedRules as $category => $rules) {
        echo "📁 {$category}:\n";

        foreach ($rules as $rule) {
            echo sprintf('  - %s%s', $rule, PHP_EOL);
        }

        echo "\n";
    }
    
    echo "💡 Tip: You can add missing rules to rules/rules.php using:\n";
    echo "use " . implode(";\nuse ", $missingRules) . ";\n";
}

/**
 * Categorize rules by their namespace
 */
function categorizeRules(array $missingRules): array
{
    $categorizedRules = [];

    foreach ($missingRules as $rule) {
        $parts = explode('\\', $rule);

        if (count($parts) >= 3) {
            $category = $parts[2];
            $categorizedRules[$category][] = $rule;
        } else {
            $categorizedRules['Other'][] = $rule;
        }
    }
    
    ksort($categorizedRules);
    
    return $categorizedRules;
}

// Run the script
main();
