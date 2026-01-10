<?php

declare(strict_types = 1);

use Rector\CodeQuality\Rector\Assign\CombinedAssignRector;
use Rector\CodeQuality\Rector\Attribute\SortAttributeNamedArgsRector;
use Rector\CodeQuality\Rector\BooleanAnd\RepeatedAndNotEqualToNotInArrayRector;
use Rector\CodeQuality\Rector\BooleanOr\RepeatedOrEqualToInArrayRector;
use Rector\CodeQuality\Rector\Catch_\ThrowWithPreviousExceptionRector;
use Rector\CodeQuality\Rector\Class_\CompleteDynamicPropertiesRector;
use Rector\CodeQuality\Rector\Class_\ConvertStaticToSelfRector;
use Rector\CodeQuality\Rector\Class_\InlineConstructorDefaultToPropertyRector;
use Rector\CodeQuality\Rector\Class_\ReturnIteratorInDataProviderRector;
use Rector\CodeQuality\Rector\ClassConstFetch\VariableConstFetchToClassConstFetchRector;
use Rector\CodeQuality\Rector\ClassMethod\InlineArrayReturnAssignRector;
use Rector\CodeQuality\Rector\ClassMethod\LocallyCalledStaticMethodToNonStaticRector;
use Rector\CodeQuality\Rector\Concat\DirnameDirConcatStringToDirectStringPathRector;
use Rector\CodeQuality\Rector\Concat\JoinStringConcatRector;
use Rector\CodeQuality\Rector\Empty_\SimplifyEmptyCheckOnEmptyArrayRector;
use Rector\CodeQuality\Rector\Expression\InlineIfToExplicitIfRector;
use Rector\CodeQuality\Rector\Expression\TernaryFalseExpressionToIfRector;
use Rector\CodeQuality\Rector\Foreach_\ForeachItemsAssignToEmptyArrayToAssignRector;
use Rector\CodeQuality\Rector\Foreach_\ForeachToInArrayRector;
use Rector\CodeQuality\Rector\Foreach_\SimplifyForeachToCoalescingRector;
use Rector\CodeQuality\Rector\Foreach_\UnusedForeachValueToArrayKeysRector;
use Rector\CodeQuality\Rector\FuncCall\ArrayMergeOfNonArraysToSimpleArrayRector;
use Rector\CodeQuality\Rector\FuncCall\ChangeArrayPushToArrayAssignRector;
use Rector\CodeQuality\Rector\FuncCall\CompactToVariablesRector;
use Rector\CodeQuality\Rector\FuncCall\RemoveSoleValueSprintfRector;
use Rector\CodeQuality\Rector\FuncCall\SimplifyInArrayValuesRector;
use Rector\CodeQuality\Rector\FuncCall\SimplifyRegexPatternRector;
use Rector\CodeQuality\Rector\FuncCall\SortCallLikeNamedArgsRector;
use Rector\CodeQuality\Rector\FuncCall\UnwrapSprintfOneArgumentRector;
use Rector\CodeQuality\Rector\FunctionLike\SimplifyUselessVariableRector;
use Rector\CodeQuality\Rector\If_\CombineIfRector;
use Rector\CodeQuality\Rector\If_\ConsecutiveNullCompareReturnsToNullCoalesceQueueRector;
use Rector\CodeQuality\Rector\If_\ShortenElseIfRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfElseToTernaryRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfNotNullReturnRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfNullableReturnRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfReturnBoolRector;
use Rector\CodeQuality\Rector\LogicalAnd\AndAssignsToSeparateLinesRector;
use Rector\CodeQuality\Rector\LogicalAnd\LogicalToBooleanRector;
use Rector\CodeQuality\Rector\NotEqual\CommonNotEqualRector;
use Rector\CodeQuality\Rector\NullsafeMethodCall\CleanupUnneededNullsafeOperatorRector;
use Rector\CodeQuality\Rector\Switch_\SwitchTrueToIfRector;
use Rector\CodeQuality\Rector\Ternary\ArrayKeyExistsTernaryThenValueToCoalescingRector;
use Rector\CodeQuality\Rector\Ternary\SimplifyTautologyTernaryRector;
use Rector\CodeQuality\Rector\Ternary\SwitchNegatedTernaryRector;
use Rector\CodeQuality\Rector\Ternary\TernaryEmptyArrayArrayDimFetchToCoalesceRector;
use Rector\CodeQuality\Rector\Ternary\UnnecessaryTernaryExpressionRector;
use Rector\CodingStyle\Rector\Assign\NestedTernaryToMatchRector;
use Rector\CodingStyle\Rector\ClassLike\NewlineBetweenClassLikeStmtsRector;
use Rector\CodingStyle\Rector\ClassMethod\BinaryOpStandaloneAssignsToDirectRector;
use Rector\CodingStyle\Rector\ClassMethod\MakeInheritedMethodVisibilitySameAsParentRector;
use Rector\CodingStyle\Rector\Encapsed\EncapsedStringsToSprintfRector;
use Rector\CodingStyle\Rector\FuncCall\ArraySpreadInsteadOfArrayMergeRector;
use Rector\CodingStyle\Rector\FuncCall\ConsistentImplodeRector;
use Rector\CodingStyle\Rector\String_\SimplifyQuoteEscapeRector;
use Rector\DeadCode\Rector\Assign\RemoveDoubleAssignRector;
use Rector\DeadCode\Rector\Assign\RemoveUnusedVariableAssignRector;
use Rector\DeadCode\Rector\Cast\RecastingRemovalRector;
use Rector\DeadCode\Rector\ClassConst\RemoveUnusedPrivateClassConstantRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveEmptyClassMethodRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveParentDelegatingConstructorRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedConstructorParamRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPrivateMethodParameterRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPrivateMethodRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPromotedPropertyRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUselessParamTagRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUselessReturnTagRector;
use Rector\DeadCode\Rector\Closure\RemoveUnusedClosureVariableUseRector;
use Rector\DeadCode\Rector\For_\RemoveDeadIfForeachForRector;
use Rector\DeadCode\Rector\FunctionLike\NarrowWideUnionReturnTypeRector;
use Rector\DeadCode\Rector\FunctionLike\RemoveDeadReturnRector;
use Rector\DeadCode\Rector\If_\ReduceAlwaysFalseIfOrRector;
use Rector\DeadCode\Rector\MethodCall\RemoveNullArgOnNullDefaultParamRector;
use Rector\DeadCode\Rector\Node\RemoveNonExistingVarAnnotationRector;
use Rector\DeadCode\Rector\Property\RemoveUnusedPrivatePropertyRector;
use Rector\DeadCode\Rector\Property\RemoveUselessReadOnlyTagRector;
use Rector\DeadCode\Rector\Property\RemoveUselessVarTagRector;
use Rector\DeadCode\Rector\StaticCall\RemoveParentCallWithoutParentRector;
use Rector\DeadCode\Rector\Stmt\RemoveConditionExactReturnRector;
use Rector\DeadCode\Rector\Stmt\RemoveNextSameValueConditionRector;
use Rector\DeadCode\Rector\Stmt\RemoveUnreachableStatementRector;
use Rector\DeadCode\Rector\Ternary\TernaryToBooleanOrFalseToBooleanAndRector;
use Rector\DeadCode\Rector\TryCatch\RemoveDeadCatchRector;
use Rector\DeadCode\Rector\TryCatch\RemoveDeadTryCatchRector;
use Rector\EarlyReturn\Rector\If_\ChangeIfElseValueAssignToEarlyReturnRector;
use Rector\EarlyReturn\Rector\If_\RemoveAlwaysElseRector;
use Rector\EarlyReturn\Rector\StmtsAwareInterface\ReturnEarlyIfVariableRector;
use Rector\Naming\Rector\Class_\RenamePropertyToMatchTypeRector;
use Rector\Php53\Rector\Ternary\TernaryToElvisRector;
use Rector\Php54\Rector\Array_\LongArrayToShortArrayRector;
use Rector\Php70\Rector\StmtsAwareInterface\IfIssetToCoalescingRector;
use Rector\Php70\Rector\Ternary\TernaryToNullCoalescingRector;
use Rector\Php71\Rector\TryCatch\MultiExceptionCatchRector;
use Rector\Php72\Rector\FuncCall\StringifyDefineRector;
use Rector\Php72\Rector\FuncCall\StringsAssertNakedRector;
use Rector\Php73\Rector\ConstFetch\SensitiveConstantNameRector;
use Rector\Php73\Rector\FuncCall\ArrayKeyFirstLastRector;
use Rector\Php73\Rector\FuncCall\JsonThrowOnErrorRector;
use Rector\Php73\Rector\FuncCall\SensitiveDefineRector;
use Rector\Php74\Rector\Assign\NullCoalescingOperatorRector;
use Rector\Php74\Rector\Closure\ClosureToArrowFunctionRector;
use Rector\Php74\Rector\Property\RestoreDefaultNullToNullableTypePropertyRector;
use Rector\Php80\Rector\Catch_\RemoveUnusedVariableInCatchRector;
use Rector\Php80\Rector\Class_\ClassPropertyAssignToConstructorPromotionRector;
use Rector\Php80\Rector\ClassMethod\AddParamBasedOnParentClassMethodRector;
use Rector\Php80\Rector\Identical\StrEndsWithRector;
use Rector\Php80\Rector\Identical\StrStartsWithRector;
use Rector\Php80\Rector\NotIdentical\StrContainsRector;
use Rector\Php80\Rector\Switch_\ChangeSwitchToMatchRector;
use Rector\Php81\Rector\ClassMethod\NewInInitializerRector;
use Rector\Php81\Rector\FuncCall\NullToStrictIntPregSlitFuncCallLimitArgRector;
use Rector\Php81\Rector\Property\ReadOnlyPropertyRector;
use Rector\Php82\Rector\Class_\ReadOnlyClassRector;
use Rector\Php82\Rector\Encapsed\VariableInStringInterpolationFixerRector;
use Rector\Php82\Rector\FuncCall\Utf8DecodeEncodeToMbConvertEncodingRector;
use Rector\Php83\Rector\Class_\ReadOnlyAnonymousClassRector;
use Rector\Php83\Rector\ClassConst\AddTypeToConstRector;
use Rector\Php84\Rector\Class_\PropertyHookRector;
use Rector\Php84\Rector\MethodCall\NewMethodCallWithoutParenthesesRector;
use Rector\Php84\Rector\Param\ExplicitNullableParamTypeRector;
use Rector\Php85\Rector\ShellExec\ShellExecFunctionCallOverBackticksRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\Class_\AnnotationWithValueToAttributeRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\ClassMethod\DataProviderAnnotationToAttributeRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\ClassMethod\DependsAnnotationWithValueToAttributeRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\ClassMethod\TestWithAnnotationToAttributeRector;
use Rector\PHPUnit\CodeQuality\Rector\Class_\ConstructClassMethodToSetUpTestCaseRector;
use Rector\PHPUnit\CodeQuality\Rector\Class_\YieldDataProviderRector;
use Rector\PHPUnit\CodeQuality\Rector\ClassMethod\DataProviderArrayItemsNewLinedRector;
use Rector\PHPUnit\CodeQuality\Rector\ClassMethod\RemoveEmptyTestMethodRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\AssertCompareOnCountableWithMethodToAssertCountRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\AssertEqualsToSameRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\AssertIssetToSpecificMethodRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\AssertNotOperatorRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\AssertSameBoolNullToSpecificMethodRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\NarrowSingleWillReturnCallbackRector;
use Rector\PHPUnit\PHPUnit100\Rector\Class_\AddProphecyTraitRector;
use Rector\PHPUnit\PHPUnit100\Rector\Class_\PublicDataProviderClassMethodRector;
use Rector\PHPUnit\PHPUnit100\Rector\Class_\StaticDataProviderClassMethodRector;
use Rector\PHPUnit\PHPUnit110\Rector\Class_\NamedArgumentForDataProviderRector;
use Rector\PHPUnit\PHPUnit70\Rector\Class_\RemoveDataProviderTestPrefixRector;
use Rector\Privatization\Rector\Class_\FinalizeTestCaseClassRector;
use Rector\Privatization\Rector\ClassConst\PrivatizeFinalClassConstantRector;
use Rector\Privatization\Rector\ClassMethod\PrivatizeFinalClassMethodRector;
use Rector\Privatization\Rector\Property\PrivatizeFinalClassPropertyRector;
use Rector\TypeDeclaration\Rector\ArrowFunction\AddArrowFunctionReturnTypeRector;
use Rector\TypeDeclaration\Rector\Class_\AddTestsVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\Class_\PropertyTypeFromStrictSetterGetterRector;
use Rector\TypeDeclaration\Rector\Class_\ReturnTypeFromStrictTernaryRector;
use Rector\TypeDeclaration\Rector\Class_\TypedStaticPropertyInBehatContextRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddMethodCallBasedStrictParamTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamFromDimFetchKeyUseRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamStringTypeFromSprintfUseRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeBasedOnPHPUnitDataProviderRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeFromPropertyTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnDocblockForScalarArrayFromAssignsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationBasedOnParentClassMethodRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\KnownMagicClassMethodTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\NarrowObjectReturnTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\NumericReturnTypeFromStrictReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\NumericReturnTypeFromStrictScalarReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByMethodCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByParentCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnNeverTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnNullableTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnCastRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnDirectArrayRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnNewRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictConstantReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictFluentReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictNativeCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictNewArrayRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictParamRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictTypedCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictTypedPropertyRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnUnionTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\StrictStringParamConcatRector;
use Rector\TypeDeclaration\Rector\Closure\AddClosureNeverReturnTypeRector;
use Rector\TypeDeclaration\Rector\Closure\AddClosureVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\Closure\ClosureReturnTypeRector;
use Rector\TypeDeclaration\Rector\FuncCall\AddArrayFunctionClosureParamTypeRector;
use Rector\TypeDeclaration\Rector\FuncCall\AddArrowFunctionParamArrayWhereDimFetchRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeForArrayMapRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeForArrayReduceRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddClosureParamTypeFromIterableMethodCallRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddParamTypeSplFixedArrayRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddReturnTypeDeclarationFromYieldsRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictConstructorRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictSetUpRector;
use Rector\TypeDeclarationDocblocks\Rector\Class_\AddReturnDocblockDataProviderRector;
use Rector\TypeDeclarationDocblocks\Rector\Class_\ClassMethodArrayDocblockParamFromLocalCallsRector;
use Rector\TypeDeclarationDocblocks\Rector\Class_\DocblockVarArrayFromGetterReturnRector;
use Rector\TypeDeclarationDocblocks\Rector\Class_\DocblockVarArrayFromPropertyDefaultsRector;
use Rector\TypeDeclarationDocblocks\Rector\Class_\DocblockVarFromParamDocblockInConstructorRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddParamArrayDocblockBasedOnArrayMapRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddParamArrayDocblockFromAssignsParamToParamReferenceRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddParamArrayDocblockFromDataProviderRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddParamArrayDocblockFromDimFetchAccessRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddReturnDocblockForArrayDimAssignedObjectRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddReturnDocblockForCommonObjectDenominatorRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\AddReturnDocblockForJsonArrayRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\DocblockGetterReturnArrayFromPropertyDocblockVarRector;
use Rector\TypeDeclarationDocblocks\Rector\ClassMethod\DocblockReturnArrayFromDirectArrayInstanceRector;
use Rector\Unambiguous\Rector\Expression\FluentSettersToStandaloneCallMethodRector;

return [
    NullToStrictIntPregSlitFuncCallLimitArgRector::class,
    KnownMagicClassMethodTypeRector::class,
    AddParamStringTypeFromSprintfUseRector::class,
    AddParamFromDimFetchKeyUseRector::class,
    BinaryOpStandaloneAssignsToDirectRector::class,
    ShellExecFunctionCallOverBackticksRector::class,
    RemoveUnusedClosureVariableUseRector::class,
    VariableConstFetchToClassConstFetchRector::class,
    RepeatedOrEqualToInArrayRector::class,
    DocblockReturnArrayFromDirectArrayInstanceRector::class,
    AddParamArrayDocblockFromDataProviderRector::class,
    AddReturnDocblockForArrayDimAssignedObjectRector::class,
    DocblockGetterReturnArrayFromPropertyDocblockVarRector::class,
    AddParamArrayDocblockFromDimFetchAccessRector::class,
    AddReturnDocblockForJsonArrayRector::class,
    AddParamArrayDocblockBasedOnArrayMapRector::class,
    AddReturnDocblockForCommonObjectDenominatorRector::class,
    AddParamArrayDocblockFromAssignsParamToParamReferenceRector::class,
    DocblockVarArrayFromPropertyDefaultsRector::class,
    DocblockVarArrayFromGetterReturnRector::class,
    DocblockVarFromParamDocblockInConstructorRector::class,
    ClassMethodArrayDocblockParamFromLocalCallsRector::class,
    ArrayKeyExistsTernaryThenValueToCoalescingRector::class,
    InlineConstructorDefaultToPropertyRector::class,
    CombineIfRector::class,
    CombinedAssignRector::class,
    CommonNotEqualRector::class,
    CompactToVariablesRector::class,
    CompleteDynamicPropertiesRector::class,
    ConsecutiveNullCompareReturnsToNullCoalesceQueueRector::class,
    ForeachItemsAssignToEmptyArrayToAssignRector::class,
    ForeachToInArrayRector::class,
    InlineArrayReturnAssignRector::class,
    JoinStringConcatRector::class,
    LogicalToBooleanRector::class,
    RemoveSoleValueSprintfRector::class,
    ShortenElseIfRector::class,
    SimplifyIfElseToTernaryRector::class,
    SimplifyIfNotNullReturnRector::class,
    SimplifyIfReturnBoolRector::class,
    SimplifyTautologyTernaryRector::class,
    SimplifyInArrayValuesRector::class,
    SimplifyRegexPatternRector::class,
    SimplifyUselessVariableRector::class,
    ThrowWithPreviousExceptionRector::class,
    UnnecessaryTernaryExpressionRector::class,
    UnusedForeachValueToArrayKeysRector::class,
    UnwrapSprintfOneArgumentRector::class,
    ReturnTypeFromStrictNewArrayRector::class,
    ReturnEarlyIfVariableRector::class,
    TypedPropertyFromStrictSetUpRector::class,
    AddParamBasedOnParentClassMethodRector::class,
    ChangeSwitchToMatchRector::class,
    StrContainsRector::class,
    StrEndsWithRector::class,
    StrStartsWithRector::class,
    AddReturnTypeDeclarationBasedOnParentClassMethodRector::class,
    AddParamTypeBasedOnPHPUnitDataProviderRector::class,
    AddReturnTypeDeclarationFromYieldsRector::class,
    ReturnTypeFromReturnDirectArrayRector::class,
    ReturnTypeFromStrictConstantReturnRector::class,
    SimplifyEmptyCheckOnEmptyArrayRector::class,
    PropertyTypeFromStrictSetterGetterRector::class,
    ReturnTypeFromStrictTernaryRector::class,
    ReturnTypeFromStrictNativeCallRector::class,
    AddArrowFunctionReturnTypeRector::class,
    AddMethodCallBasedStrictParamTypeRector::class,
    AddParamTypeFromPropertyTypeRector::class,
    AddReturnTypeDeclarationBasedOnParentClassMethodRector::class,
    AddReturnTypeDeclarationFromYieldsRector::class,
    ParamTypeByMethodCallTypeRector::class,
    ParamTypeByParentCallTypeRector::class,
    ReturnNeverTypeRector::class,
    ReturnTypeFromReturnDirectArrayRector::class,
    ReturnTypeFromReturnNewRector::class,
    ReturnTypeFromStrictTypedCallRector::class,
    ReturnTypeFromStrictTypedPropertyRector::class,
    TypedPropertyFromStrictConstructorRector::class,
    ReadOnlyPropertyRector::class,
    SwitchTrueToIfRector::class,
    NewInInitializerRector::class,
    IfIssetToCoalescingRector::class,
    CleanupUnneededNullsafeOperatorRector::class,
    ReadOnlyClassRector::class,
    Utf8DecodeEncodeToMbConvertEncodingRector::class,
    PrivatizeFinalClassMethodRector::class,
    PrivatizeFinalClassPropertyRector::class,
    AddParamTypeSplFixedArrayRector::class,
    AndAssignsToSeparateLinesRector::class,
    ChangeArrayPushToArrayAssignRector::class,
    ConvertStaticToSelfRector::class,
    InlineIfToExplicitIfRector::class,
    SimplifyForeachToCoalescingRector::class,
    SwitchNegatedTernaryRector::class,
    TernaryEmptyArrayArrayDimFetchToCoalesceRector::class,
    TernaryFalseExpressionToIfRector::class,
    MakeInheritedMethodVisibilitySameAsParentRector::class,
    EncapsedStringsToSprintfRector::class,
    RecastingRemovalRector::class,
    RemoveDeadReturnRector::class,
    RemoveDeadTryCatchRector::class,
    RemoveDoubleAssignRector::class,
    RemoveEmptyClassMethodRector::class,
    RemoveNonExistingVarAnnotationRector::class,
    RemoveParentCallWithoutParentRector::class,
    RemoveUnreachableStatementRector::class,
    RemoveUnusedConstructorParamRector::class,
    RemoveUnusedPrivateClassConstantRector::class,
    RemoveUnusedPrivateMethodParameterRector::class,
    RemoveUnusedPrivateMethodRector::class,
    RemoveUnusedPromotedPropertyRector::class,
    RemoveUnusedVariableAssignRector::class,
    RemoveUselessVarTagRector::class,
    TernaryToBooleanOrFalseToBooleanAndRector::class,
    RemoveAlwaysElseRector::class,
    RenamePropertyToMatchTypeRector::class,
    DataProviderAnnotationToAttributeRector::class,
    TestWithAnnotationToAttributeRector::class,
    NumericReturnTypeFromStrictScalarReturnsRector::class,
    StrictStringParamConcatRector::class,
    ReturnTypeFromStrictParamRector::class,
    ReturnUnionTypeRector::class,
    ReadOnlyClassRector::class,
    RemoveUselessReturnTagRector::class,
    RemoveUselessParamTagRector::class,
    PrivatizeFinalClassMethodRector::class,
    RestoreDefaultNullToNullableTypePropertyRector::class,
    AddTestsVoidReturnTypeWhereNoReturnRector::class,
    ExplicitNullableParamTypeRector::class,
    ReduceAlwaysFalseIfOrRector::class,
    VariableInStringInterpolationFixerRector::class,
    RemoveUselessReadOnlyTagRector::class,
    ReturnTypeFromReturnCastRector::class,
    AddClosureNeverReturnTypeRector::class,
    ReturnNullableTypeRector::class,
    AddTypeToConstRector::class,
    StringifyDefineRector::class,
    TernaryToElvisRector::class,
    TernaryToNullCoalescingRector::class,
    LocallyCalledStaticMethodToNonStaticRector::class,
    NewMethodCallWithoutParenthesesRector::class,
    SensitiveDefineRector::class,
    SensitiveConstantNameRector::class,
    // PHPUnit
    FinalizeTestCaseClassRector::class,
    StaticDataProviderClassMethodRector::class,
    AddProphecyTraitRector::class,
    AssertIssetToSpecificMethodRector::class,
    ConstructClassMethodToSetUpTestCaseRector::class,
    DependsAnnotationWithValueToAttributeRector::class,
    RemoveDataProviderTestPrefixRector::class,
    RemoveEmptyTestMethodRector::class,
    DataProviderArrayItemsNewLinedRector::class,
    NamedArgumentForDataProviderRector::class,
    PublicDataProviderClassMethodRector::class,
    YieldDataProviderRector::class,
    SimplifyIfNullableReturnRector::class,
    RemoveDeadCatchRector::class,
    RemoveDeadIfForeachForRector::class,
    ReadOnlyAnonymousClassRector::class,
    NamedArgumentForDataProviderRector::class,
    NarrowSingleWillReturnCallbackRector::class,
    NullCoalescingOperatorRector::class,
    MultiExceptionCatchRector::class,
    ClosureToArrowFunctionRector::class,
    ConsistentImplodeRector::class,
    ChangeIfElseValueAssignToEarlyReturnRector::class,
    AddProphecyTraitRector::class,
    AddReturnTypeDeclarationRector::class,
    AnnotationWithValueToAttributeRector::class,
    ArrayKeyFirstLastRector::class,
    ArrayMergeOfNonArraysToSimpleArrayRector::class,
    ArraySpreadInsteadOfArrayMergeRector::class,
    AssertCompareOnCountableWithMethodToAssertCountRector::class,
    AssertEqualsToSameRector::class,
    AssertIssetToSpecificMethodRector::class,
    AssertNotOperatorRector::class,
    AssertSameBoolNullToSpecificMethodRector::class,
    AddReturnDocblockDataProviderRector::class,
    ReturnIteratorInDataProviderRector::class,
    RepeatedAndNotEqualToNotInArrayRector::class,
    DirnameDirConcatStringToDirectStringPathRector::class,
    RemoveConditionExactReturnRector::class,
    PropertyHookRector::class,
    TypedStaticPropertyInBehatContextRector::class,
    SortAttributeNamedArgsRector::class,
    SortCallLikeNamedArgsRector::class,
    RemoveParentDelegatingConstructorRector::class,
    NarrowWideUnionReturnTypeRector::class,
    RemoveNextSameValueConditionRector::class,
    FluentSettersToStandaloneCallMethodRector::class,
    PrivatizeFinalClassConstantRector::class,
    NestedTernaryToMatchRector::class,
    NewlineBetweenClassLikeStmtsRector::class,
    SimplifyQuoteEscapeRector::class,
    NarrowObjectReturnTypeRector::class,
    RemoveNullArgOnNullDefaultParamRector::class,
    StringsAssertNakedRector::class,
    RemoveUnusedVariableInCatchRector::class,
    ClassPropertyAssignToConstructorPromotionRector::class,
    JsonThrowOnErrorRector::class,
    ClosureReturnTypeRector::class,
    AddClosureVoidReturnTypeWhereNoReturnRector::class,
    AddArrowFunctionParamArrayWhereDimFetchRector::class,
    AddArrayFunctionClosureParamTypeRector::class,
    AddClosureParamTypeForArrayMapRector::class,
    AddClosureParamTypeFromIterableMethodCallRector::class,
    AddClosureParamTypeForArrayReduceRector::class,
    AddVoidReturnTypeWhereNoReturnRector::class,
    NumericReturnTypeFromStrictReturnsRector::class,
    ReturnTypeFromStrictFluentReturnRector::class,
    AddReturnDocblockForScalarArrayFromAssignsRector::class,
    LongArrayToShortArrayRector::class,
    RemoveUnusedPrivatePropertyRector::class,
];
