
module DDC.Core.Flow.Transform.Slurp.Operator
        ( slurpOperator
        , isFlowOperator)
where
import DDC.Core.Flow.Process.Operator
import DDC.Core.Flow.Exp
import DDC.Core.Flow.Prim
import DDC.Core.Flow.Prim.TyConPrim
import DDC.Core.Compounds.Simple
import DDC.Type.Pretty          ()
import Control.Monad


-- | Slurp a stream operator from a let-binding binding.
--   We use this when recovering operators from the source program.
slurpOperator 
        :: Bind Name 
        -> Exp () Name 
        -> Maybe Operator

slurpOperator bResult xx

 -- Map -----------------------------------------
 | Just (NameOpFlow (OpFlowMap n), xs) 
                                <- takeXPrimApps xx
 , n >= 1
 , XType tR : xsArgs2   <- xs
 , (xsA, xsArgs3)       <- splitAt (n + 1) xsArgs2
 , tsA                  <- [ t | XType t <- xsA ]
 , length tsA      == n + 1
 , xWorker : xsSeries   <- xsArgs3
 , usSeries             <- [ u | XVar u  <- xsSeries ]
 , length usSeries == n
 , Just (psIn, xBody)           <- takeXLams xWorker
 , length psIn     == n
 = Just $ OpMap
        { opArity               = n
        , opResultSeries        = bResult
        , opInputRate           = tR
        , opInputSeriess        = usSeries
        , opWorkerParams        = psIn
        , opWorkerBody          = xBody }


 -- Pack ----------------------------------------
 | Just ( NameOpFlow OpFlowPack
        , [ XType tRateInput, XType tRateOutput, XType tElem
          , _xSel, (XVar uSeries) ])    <- takeXPrimApps xx
 = Just $ OpPack
        { opResultSeries        = bResult
        , opInputRate           = tRateInput
        , opInputSeries         = uSeries
        , opOutputRate          = tRateOutput 
        , opElemType            = tElem }


 -- Reduce --------------------------------------
 | Just ( NameOpFlow OpFlowReduce
        , [ XType tK, XType _
          , XVar uRef, xWorker, xZ, XVar uS ])
                                <- takeXPrimApps xx
 , Just ([bAcc, bElem], xBody)  <- takeXLams xWorker
 = Just $ OpReduce
        { opResultBind          = bResult
        , opTargetRef           = uRef
        , opInputRate           = tK
        , opInputSeries         = uS
        , opZero                = xZ
        , opWorkerParamAcc      = bAcc
        , opWorkerParamElem     = bElem
        , opWorkerBody          = xBody }


 -- Fold ----------------------------------------
 | Just ( NameOpFlow OpFlowFold
        , [ XType tRate, XType _tAcc, XType _tElem
          , xWorker,     xZero,     (XVar uSeries)])
                                <- takeXPrimApps xx
 , Just ([pAcc, pElem], xBody)  <- takeXLams xWorker
 = Just $ OpFold
        { opResultValue         = bResult
        , opInputRate           = tRate
        , opInputSeries         = uSeries
        , opZero                = xZero
        , opWorkerParamIndex    = BNone tInt
        , opWorkerParamAcc      = pAcc
        , opWorkerParamElem     = pElem
        , opWorkerBody          = xBody }


 -- FoldIndex -----------------------------------
 | Just ( NameOpFlow OpFlowFoldIndex
        , [ XType tRate, XType _tAcc, XType _tElem
          , xWorker,     xZero,     (XVar uSeries)])
                                    <- takeXPrimApps xx
 , Just ([pIx, pAcc, pElem], xBody) <- takeXLams xWorker
 = Just $ OpFold
        { opResultValue         = bResult
        , opInputRate           = tRate
        , opInputSeries         = uSeries
        , opZero                = xZero
        , opWorkerParamIndex    = pIx
        , opWorkerParamAcc      = pAcc
        , opWorkerParamElem     = pElem
        , opWorkerBody          = xBody }


 -- Create --------------------------------------
 | Just ( NameOpFlow OpFlowCreate
        , [ XType tK, XType tA, XVar uSeries ])
                                <- takeXPrimApps xx
 = Just $ OpCreate
        { opResultVector        = bResult
        , opInputRate           = tK
        , opInputSeries         = uSeries 
        , opAllocRate           = Nothing
        , opElemType            = tA }


 -- Fill ----------------------------------------
 | Just ( NameOpFlow OpFlowFill
        , [ XType tK, XType tA, XVar uV, XVar uS ])
                                <- takeXPrimApps xx
 = Just $ OpFill
        { opResultBind          = bResult
        , opTargetVector        = uV
        , opInputRate           = tK 
        , opInputSeries         = uS
        , opElemType            = tA }


 -- Gather --------------------------------------
 | Just ( NameOpFlow OpFlowGather
        , [ XType tK, XType tA, XVar uV, XVar uS ])
                                <- takeXPrimApps xx
 = Just $ OpGather
        { opResultBind          = bResult
        , opSourceVector        = uV
        , opSourceIndices       = uS
        , opInputRate           = tK
        , opElemType            = tA }


 -- Scatter -------------------------------------
 | Just ( NameOpFlow OpFlowScatter
        , [ XType tK, XType tA, XVar uV, XVar uIndices, XVar uElems ])
                                <- takeXPrimApps xx
 = Just $ OpScatter
        { opResultBind          = bResult
        , opTargetVector        = uV
        , opSourceIndices       = uIndices
        , opSourceElems         = uElems
        , opInputRate           = tK
        , opElemType            = tA }

 | otherwise
 = Nothing


-- | Check if some binding is a flow operator.
isFlowOperator 
        :: Exp () Name 
        -> Bool

isFlowOperator xx
 = case liftM fst $ takeXPrimApps xx of
        Just (NameOpFlow OpFlowCreate)    -> True
        Just (NameOpFlow (OpFlowMap _))   -> True
        Just (NameOpFlow OpFlowReduce)    -> True
        Just (NameOpFlow OpFlowFold)      -> True
        Just (NameOpFlow OpFlowFoldIndex) -> True
        Just (NameOpFlow OpFlowPack)      -> True
        Just (NameOpFlow (OpFlowMkSel _)) -> True
        Just (NameOpFlow OpFlowFill)      -> True
        Just (NameOpFlow OpFlowGather)    -> True
        Just (NameOpFlow OpFlowScatter)   -> True
        _                                 -> False

