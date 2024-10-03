<?php

declare(strict_types = 1);

use Rector\CodeQuality\Rector\Assign\CombinedAssignRector;
use Rector\CodeQuality\Rector\Catch_\ThrowWithPreviousExceptionRector;
use Rector\CodeQuality\Rector\Class_\CompleteDynamicPropertiesRector;
use Rector\CodeQuality\Rector\Class_\InlineConstructorDefaultToPropertyRector;
use Rector\CodeQuality\Rector\Class_\StaticToSelfStaticMethodCallOnFinalClassRector;
use Rector\CodeQuality\Rector\ClassConstFetch\ConvertStaticPrivateConstantToSelfRector;
use Rector\CodeQuality\Rector\ClassMethod\InlineArrayReturnAssignRector;
use Rector\CodeQuality\Rector\ClassMethod\LocallyCalledStaticMethodToNonStaticRector;
use Rector\CodeQuality\Rector\Concat\JoinStringConcatRector;
use Rector\CodeQuality\Rector\Empty_\SimplifyEmptyCheckOnEmptyArrayRector;
use Rector\CodeQuality\Rector\Expression\InlineIfToExplicitIfRector;
use Rector\CodeQuality\Rector\Expression\TernaryFalseExpressionToIfRector;
use Rector\CodeQuality\Rector\Foreach_\ForeachItemsAssignToEmptyArrayToAssignRector;
use Rector\CodeQuality\Rector\Foreach_\ForeachToInArrayRector;
use Rector\CodeQuality\Rector\Foreach_\SimplifyForeachToCoalescingRector;
use Rector\CodeQuality\Rector\Foreach_\UnusedForeachValueToArrayKeysRector;
use Rector\CodeQuality\Rector\FuncCall\ChangeArrayPushToArrayAssignRector;
use Rector\CodeQuality\Rector\FuncCall\CompactToVariablesRector;
use Rector\CodeQuality\Rector\FuncCall\RemoveSoleValueSprintfRector;
use Rector\CodeQuality\Rector\FuncCall\SimplifyInArrayValuesRector;
use Rector\CodeQuality\Rector\FuncCall\SimplifyRegexPatternRector;
use Rector\CodeQuality\Rector\FuncCall\UnwrapSprintfOneArgumentRector;
use Rector\CodeQuality\Rector\FunctionLike\SimplifyUselessVariableRector;
use Rector\CodeQuality\Rector\If_\CombineIfRector;
use Rector\CodeQuality\Rector\If_\ConsecutiveNullCompareReturnsToNullCoalesceQueueRector;
use Rector\CodeQuality\Rector\If_\ShortenElseIfRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfElseToTernaryRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfNotNullReturnRector;
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
use Rector\CodingStyle\Rector\ArrowFunction\StaticArrowFunctionRector;
use Rector\CodingStyle\Rector\ClassMethod\MakeInheritedMethodVisibilitySameAsParentRector;
use Rector\CodingStyle\Rector\Encapsed\EncapsedStringsToSprintfRector;
use Rector\DeadCode\Rector\Assign\RemoveDoubleAssignRector;
use Rector\DeadCode\Rector\Assign\RemoveUnusedVariableAssignRector;
use Rector\DeadCode\Rector\Cast\RecastingRemovalRector;
use Rector\DeadCode\Rector\ClassConst\RemoveUnusedPrivateClassConstantRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveEmptyClassMethodRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedConstructorParamRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPrivateMethodParameterRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPrivateMethodRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUnusedPromotedPropertyRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUselessParamTagRector;
use Rector\DeadCode\Rector\ClassMethod\RemoveUselessReturnTagRector;
use Rector\DeadCode\Rector\FunctionLike\RemoveDeadReturnRector;
use Rector\DeadCode\Rector\If_\ReduceAlwaysFalseIfOrRector;
use Rector\DeadCode\Rector\Node\RemoveNonExistingVarAnnotationRector;
use Rector\DeadCode\Rector\Property\RemoveUselessReadOnlyTagRector;
use Rector\DeadCode\Rector\Property\RemoveUselessVarTagRector;
use Rector\DeadCode\Rector\StaticCall\RemoveParentCallWithoutParentRector;
use Rector\DeadCode\Rector\Stmt\RemoveUnreachableStatementRector;
use Rector\DeadCode\Rector\Ternary\TernaryToBooleanOrFalseToBooleanAndRector;
use Rector\DeadCode\Rector\TryCatch\RemoveDeadTryCatchRector;
use Rector\EarlyReturn\Rector\If_\RemoveAlwaysElseRector;
use Rector\EarlyReturn\Rector\StmtsAwareInterface\ReturnEarlyIfVariableRector;
use Rector\Naming\Rector\Class_\RenamePropertyToMatchTypeRector;
use Rector\Php53\Rector\Ternary\TernaryToElvisRector;
use Rector\Php70\Rector\StmtsAwareInterface\IfIssetToCoalescingRector;
use Rector\Php70\Rector\Ternary\TernaryToNullCoalescingRector;
use Rector\Php72\Rector\FuncCall\StringifyDefineRector;
use Rector\Php74\Rector\Property\RestoreDefaultNullToNullableTypePropertyRector;
use Rector\Php80\Rector\ClassMethod\AddParamBasedOnParentClassMethodRector;
use Rector\Php80\Rector\Identical\StrEndsWithRector;
use Rector\Php80\Rector\Identical\StrStartsWithRector;
use Rector\Php80\Rector\NotIdentical\StrContainsRector;
use Rector\Php80\Rector\Switch_\ChangeSwitchToMatchRector;
use Rector\Php81\Rector\ClassMethod\NewInInitializerRector;
use Rector\Php81\Rector\Property\ReadOnlyPropertyRector;
use Rector\Php82\Rector\Class_\ReadOnlyClassRector;
use Rector\Php82\Rector\Encapsed\VariableInStringInterpolationFixerRector;
use Rector\Php82\Rector\FuncCall\Utf8DecodeEncodeToMbConvertEncodingRector;
use Rector\Php83\Rector\ClassConst\AddTypeToConstRector;
use Rector\Php84\Rector\Param\ExplicitNullableParamTypeRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\ClassMethod\DataProviderAnnotationToAttributeRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\ClassMethod\DependsAnnotationWithValueToAttributeRector;
use Rector\PHPUnit\AnnotationsToAttributes\Rector\ClassMethod\TestWithAnnotationToAttributeRector;
use Rector\PHPUnit\CodeQuality\Rector\Class_\ConstructClassMethodToSetUpTestCaseRector;
use Rector\PHPUnit\CodeQuality\Rector\Class_\YieldDataProviderRector;
use Rector\PHPUnit\CodeQuality\Rector\ClassMethod\DataProviderArrayItemsNewLinedRector;
use Rector\PHPUnit\CodeQuality\Rector\ClassMethod\RemoveEmptyTestMethodRector;
use Rector\PHPUnit\CodeQuality\Rector\MethodCall\AssertIssetToSpecificMethodRector;
use Rector\PHPUnit\PHPUnit100\Rector\Class_\AddProphecyTraitRector;
use Rector\PHPUnit\PHPUnit100\Rector\Class_\PublicDataProviderClassMethodRector;
use Rector\PHPUnit\PHPUnit100\Rector\Class_\StaticDataProviderClassMethodRector;
use Rector\PHPUnit\PHPUnit110\Rector\Class_\NamedArgumentForDataProviderRector;
use Rector\PHPUnit\PHPUnit70\Rector\Class_\RemoveDataProviderTestPrefixRector;
use Rector\Privatization\Rector\Class_\FinalizeTestCaseClassRector;
use Rector\Privatization\Rector\ClassMethod\PrivatizeFinalClassMethodRector;
use Rector\Privatization\Rector\Property\PrivatizeFinalClassPropertyRector;
use Rector\TypeDeclaration\Rector\ArrowFunction\AddArrowFunctionReturnTypeRector;
use Rector\TypeDeclaration\Rector\Class_\AddTestsVoidReturnTypeWhereNoReturnRector;
use Rector\TypeDeclaration\Rector\Class_\PropertyTypeFromStrictSetterGetterRector;
use Rector\TypeDeclaration\Rector\Class_\ReturnTypeFromStrictTernaryRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddMethodCallBasedStrictParamTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeBasedOnPHPUnitDataProviderRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeFromPropertyTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationBasedOnParentClassMethodRector;
use Rector\TypeDeclaration\Rector\ClassMethod\NumericReturnTypeFromStrictScalarReturnsRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByMethodCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByParentCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnNeverTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnNullableTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnCastRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnDirectArrayRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnNewRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictConstantReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictNativeCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictNewArrayRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictParamRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictTypedCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictTypedPropertyRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnUnionTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\StrictStringParamConcatRector;
use Rector\TypeDeclaration\Rector\Closure\AddClosureNeverReturnTypeRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddParamTypeSplFixedArrayRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddReturnTypeDeclarationFromYieldsRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictConstructorRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictSetUpRector;

return [
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
    StaticArrowFunctionRector::class,
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
    ConvertStaticPrivateConstantToSelfRector::class,
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
    StaticToSelfStaticMethodCallOnFinalClassRector::class,
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
];
