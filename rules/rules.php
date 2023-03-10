<?php

declare(strict_types = 1);

use Rector\CodeQuality\Rector\Assign\CombinedAssignRector;
use Rector\CodeQuality\Rector\Catch_\ThrowWithPreviousExceptionRector;
use Rector\CodeQuality\Rector\Class_\CompleteDynamicPropertiesRector;
use Rector\CodeQuality\Rector\Class_\InlineConstructorDefaultToPropertyRector;
use Rector\CodeQuality\Rector\ClassMethod\InlineArrayReturnAssignRector;
use Rector\CodeQuality\Rector\ClassMethod\ReturnTypeFromStrictScalarReturnExprRector;
use Rector\CodeQuality\Rector\Concat\JoinStringConcatRector;
use Rector\CodeQuality\Rector\Empty_\SimplifyEmptyCheckOnEmptyArrayRector;
use Rector\CodeQuality\Rector\For_\ForToForeachRector;
use Rector\CodeQuality\Rector\Foreach_\ForeachItemsAssignToEmptyArrayToAssignRector;
use Rector\CodeQuality\Rector\Foreach_\ForeachToInArrayRector;
use Rector\CodeQuality\Rector\Foreach_\SimplifyForeachToArrayFilterRector;
use Rector\CodeQuality\Rector\Foreach_\UnusedForeachValueToArrayKeysRector;
use Rector\CodeQuality\Rector\FuncCall\CompactToVariablesRector;
use Rector\CodeQuality\Rector\FuncCall\IntvalToTypeCastRector;
use Rector\CodeQuality\Rector\FuncCall\RemoveSoleValueSprintfRector;
use Rector\CodeQuality\Rector\FuncCall\UnwrapSprintfOneArgumentRector;
use Rector\CodeQuality\Rector\FunctionLike\SimplifyUselessVariableRector;
use Rector\CodeQuality\Rector\If_\CombineIfRector;
use Rector\CodeQuality\Rector\If_\ConsecutiveNullCompareReturnsToNullCoalesceQueueRector;
use Rector\CodeQuality\Rector\If_\ShortenElseIfRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfElseToTernaryRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfNotNullReturnRector;
use Rector\CodeQuality\Rector\If_\SimplifyIfNullableReturnRector;
use Rector\CodeQuality\Rector\LogicalAnd\LogicalToBooleanRector;
use Rector\CodeQuality\Rector\NotEqual\CommonNotEqualRector;
use Rector\CodeQuality\Rector\Ternary\ArrayKeyExistsTernaryThenValueToCoalescingRector;
use Rector\CodeQuality\Rector\Ternary\SimplifyTautologyTernaryRector;
use Rector\CodeQuality\Rector\Ternary\UnnecessaryTernaryExpressionRector;
use Rector\CodingStyle\Rector\ArrowFunction\StaticArrowFunctionRector;
use Rector\CodingStyle\Rector\Property\NullifyUnionNullableRector;
use Rector\DeadCode\Rector\StmtsAwareInterface\RemoveJustVariableAssignRector;
use Rector\EarlyReturn\Rector\StmtsAwareInterface\ReturnEarlyIfVariableRector;
use Rector\Php80\Rector\ClassMethod\AddParamBasedOnParentClassMethodRector;
use Rector\Php80\Rector\Identical\StrEndsWithRector;
use Rector\Php80\Rector\Identical\StrStartsWithRector;
use Rector\Php80\Rector\NotIdentical\StrContainsRector;
use Rector\Php80\Rector\Switch_\ChangeSwitchToMatchRector;
use Rector\Php81\Rector\Property\ReadOnlyPropertyRector;
use Rector\TypeDeclaration\Rector\ArrowFunction\AddArrowFunctionReturnTypeRector;
use Rector\TypeDeclaration\Rector\Class_\PropertyTypeFromStrictSetterGetterRector;
use Rector\TypeDeclaration\Rector\Class_\ReturnTypeFromStrictTernaryRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddMethodCallBasedStrictParamTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeBasedOnPHPUnitDataProviderRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddParamTypeFromPropertyTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\AddReturnTypeDeclarationBasedOnParentClassMethodRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ArrayShapeFromConstantArrayReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByMethodCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ParamTypeByParentCallTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnAnnotationIncorrectNullableRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnNeverTypeRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnDirectArrayRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromReturnNewRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictBoolReturnExprRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictConstantReturnRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictNativeCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictNewArrayRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictTypedCallRector;
use Rector\TypeDeclaration\Rector\ClassMethod\ReturnTypeFromStrictTypedPropertyRector;
use Rector\TypeDeclaration\Rector\Closure\AddClosureReturnTypeRector;
use Rector\TypeDeclaration\Rector\FunctionLike\AddReturnTypeDeclarationFromYieldsRector;
use Rector\TypeDeclaration\Rector\Param\ParamTypeFromStrictTypedPropertyRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictConstructorRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictGetterMethodReturnTypeRector;
use Rector\TypeDeclaration\Rector\Property\TypedPropertyFromStrictSetUpRector;
use Rector\TypeDeclaration\Rector\Property\VarAnnotationIncorrectNullableRector;

return [
    ArrayKeyExistsTernaryThenValueToCoalescingRector::class,
    InlineConstructorDefaultToPropertyRector::class,
    CombineIfRector::class,
    CombinedAssignRector::class,
    CommonNotEqualRector::class,
    CompactToVariablesRector::class,
    CompleteDynamicPropertiesRector::class,
    ConsecutiveNullCompareReturnsToNullCoalesceQueueRector::class,
    ForToForeachRector::class,
    ForeachItemsAssignToEmptyArrayToAssignRector::class,
    ForeachToInArrayRector::class,
    InlineArrayReturnAssignRector::class,
    IntvalToTypeCastRector::class,
    JoinStringConcatRector::class,
    LogicalToBooleanRector::class,
    RemoveSoleValueSprintfRector::class,
    ShortenElseIfRector::class,
    SimplifyForeachToArrayFilterRector::class,
    SimplifyIfElseToTernaryRector::class,
    SimplifyIfNotNullReturnRector::class,
    SimplifyIfNullableReturnRector::class,
    SimplifyTautologyTernaryRector::class,
    SimplifyUselessVariableRector::class,
    ThrowWithPreviousExceptionRector::class,
    UnnecessaryTernaryExpressionRector::class,
    UnusedForeachValueToArrayKeysRector::class,
    UnwrapSprintfOneArgumentRector::class,
    ReturnTypeFromStrictNewArrayRector::class,
    ReturnTypeFromStrictScalarReturnExprRector::class,
    ReturnEarlyIfVariableRector::class,
    RemoveJustVariableAssignRector::class,
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
    NullifyUnionNullableRector::class,
    PropertyTypeFromStrictSetterGetterRector::class,
    ReturnTypeFromStrictTernaryRector::class,
    ReturnTypeFromStrictNativeCallRector::class,
    AddArrowFunctionReturnTypeRector::class,
    AddClosureReturnTypeRector::class,
    AddMethodCallBasedStrictParamTypeRector::class,
    AddParamTypeFromPropertyTypeRector::class,
    AddReturnTypeDeclarationBasedOnParentClassMethodRector::class,
    AddReturnTypeDeclarationFromYieldsRector::class,
    ArrayShapeFromConstantArrayReturnRector::class,
    ParamTypeByMethodCallTypeRector::class,
    ParamTypeByParentCallTypeRector::class,
    ParamTypeFromStrictTypedPropertyRector::class,
    ReturnAnnotationIncorrectNullableRector::class,
    ReturnNeverTypeRector::class,
    ReturnTypeFromReturnDirectArrayRector::class,
    ReturnTypeFromReturnNewRector::class,
    ReturnTypeFromStrictBoolReturnExprRector::class,
    ReturnTypeFromStrictTypedCallRector::class,
    ReturnTypeFromStrictTypedPropertyRector::class,
    TypedPropertyFromStrictConstructorRector::class,
    TypedPropertyFromStrictGetterMethodReturnTypeRector::class,
    VarAnnotationIncorrectNullableRector::class,
    ReadOnlyPropertyRector::class,
];