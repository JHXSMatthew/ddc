-- | Bindings to functions exported by the runtime system,
--   and wrappers for related primops.
module DDC.Core.Salt.Runtime
        ( -- * Runtime Config
          Config  (..)
        , runtimeImportKinds
        , runtimeImportTypes

          -- * Runtime Types.
        , rTop

          -- * Runtime Functions
          -- ** Generic
        , xTagOfObject

          -- ** Boxed Objects
        , xAllocBoxed
        , xGetFieldOfBoxed
        , xSetFieldOfBoxed

          -- ** Raw Objects
        , xAllocRaw
        , xPayloadOfRaw

          -- ** Raw Small Objects
        , xAllocSmall
        , xPayloadOfSmall

          -- ** Thunk Objects
        , xAllocThunk
        , xArgsOfThunk
        , xSetFieldOfThunk
        , xExtendThunk
        , xCopyArgsOfThunk
        , xApplyThunk
        , xRunThunk

          -- ** Allocator
        , xddcInit
        , xddcExit
        , xAllocCollect

          -- ** Error handling
        , xErrorDefault

          -- * Calls to primops.
        , xCreate
        , xAllocSlot
        , xAllocSlotVal
        , xRead
        , xWrite
        , xPeek
        , xPoke
        , xCast
        , xFail
        , xReturn)
where
import DDC.Core.Salt.Compounds
import DDC.Core.Salt.Name
import DDC.Core.Exp.Annot
import DDC.Core.Module
import DDC.Data.Pretty
import qualified Data.Map       as Map
import Data.Map                 (Map)


-- Runtime -----------------------------------------------------------------------------------------
-- | Runtime system configuration
data Config
        = Config
        { -- | Use two fixed-size heaps of this many bytes. We allocate two
          --   heaps as the garbage collector is a two-space copying collector.
          configHeapSize        :: Integer
        }


-- | Kind signatures for runtime types that we use when converting to Salt.
runtimeImportKinds :: Map Name (ImportType Name (Type Name))
runtimeImportKinds
 = Map.fromList
   [ rn ukTop ]
 where   rn (UName n, t)  = (n, ImportTypeAbstract t)
         rn _   = error "ddc-core-salt: all runtime bindings must be named."


-- | Type signatures for runtime funtions that we use when converting to Salt.
runtimeImportTypes :: Map Name (ImportValue Name (Type Name))
runtimeImportTypes
 = Map.fromList 
   [ rn utTagOfObject

   , rn utAllocBoxed
   , rn utGetFieldOfBoxed
   , rn utSetFieldOfBoxed

   , rn utAllocSmall
   , rn utPayloadOfSmall 

   , rn utAllocRaw
   , rn utPayloadOfRaw

   , rn utAllocThunk 
   , rn utArgsOfThunk
   , rn utSetFieldOfThunk
   , rn utExtendThunk
   , rn utCopyArgsOfThunk 
   , rn utRunThunk

   , rn (utApplyThunk 0)
   , rn (utApplyThunk 1)
   , rn (utApplyThunk 2)
   , rn (utApplyThunk 3)
   , rn (utApplyThunk 4) 

   , rn utddcInit
   , rn utddcExit
   , rn utTagOfObject

   , rn utErrorDefault]

 where   rn (UName n, t)  = (n, ImportValueSea (renderPlain $ ppr n) t)
         rn _   = error "ddc-core-salt: all runtime bindings must be named."


-- Tags -------------------------------------------------------------------------------------------
-- | Get the constructor tag of an object.
xTagOfObject :: a -> Type Name -> Exp a Name -> Exp a Name
xTagOfObject a tR x2
 = xApps a (XVar a $ fst utTagOfObject)
        [ XType a tR, x2 ]

utTagOfObject :: (Bound Name, Type Name)
utTagOfObject
 =      ( UName (NameVar "ddcTagOfObject")
        ,       tForall kRegion $ \r -> tPtr r tObj `tFun` tTag)


-- Thunk ------------------------------------------------------------------------------------------
-- | Allocate a Thunk object.
xAllocThunk  
        :: a 
        -> Type Name 
        -> Exp a Name   -- ^ Function
        -> Exp a Name   -- ^ Value paramters.
        -> Exp a Name   -- ^ Times boxed.
        -> Exp a Name   -- ^ Value args.
        -> Exp a Name   -- ^ Times run.
        -> Exp a Name

xAllocThunk a tR xFun xParam xBoxes xArgs xRun
 = xApps a (XVar a $ fst utAllocThunk)
        [ XType a tR, xFun, xParam, xBoxes, xArgs, xRun]

utAllocThunk :: (Bound Name, Type Name)
utAllocThunk
 =      ( UName (NameVar "ddcAllocThunk")
        , tForall kRegion 
           $ \tR -> (tAddr `tFun` tNat `tFun` tNat `tFun` tNat 
                           `tFun` tNat `tFun` tPtr tR tObj))


-- | Copy the available arguments from one thunk to another.
xCopyArgsOfThunk
        :: a -> Type Name -> Type Name
        -> Exp a Name -> Exp a Name -> Exp a Name -> Exp a Name -> Exp a Name

xCopyArgsOfThunk a tRSrc tRDst xSrc xDst xIndex xLen
 = xApps a (XVar a $ fst utCopyArgsOfThunk)
        [ XType a tRSrc, XType a tRDst, xSrc, xDst, xIndex, xLen ]


utCopyArgsOfThunk :: (Bound Name, Type Name)
utCopyArgsOfThunk
 =      ( UName (NameVar "ddcCopyThunk")
        , tForalls [kRegion, kRegion]
           $ \[tR1, tR2] -> (tPtr tR1 tObj 
                                `tFun` tPtr tR2 tObj
                                `tFun` tNat `tFun` tNat 
                                `tFun` tPtr tR2 tObj))


-- | Copy a thunk while extending the number of available argument slots.
xExtendThunk
        :: a -> Type Name -> Type Name
        -> Exp a Name -> Exp a Name -> Exp a Name

xExtendThunk a tRSrc tRDst xSrc xMore
 = xApps a (XVar a $ fst utExtendThunk)
        [ XType a tRSrc, XType a tRDst, xSrc, xMore ]

utExtendThunk :: (Bound Name, Type Name)
utExtendThunk
 =      ( UName (NameVar "ddcExtendThunk")
        , tForalls [kRegion, kRegion]
           $ \[tR1, tR2] -> (tPtr tR1 tObj `tFun` tNat `tFun` tPtr tR2 tObj))


-- | Get the available arguments in a thunk.
xArgsOfThunk
        :: a -> Type Name
        -> Exp a Name -> Exp a Name

xArgsOfThunk a tR xThunk
 = xApps a (XVar a $ fst utArgsOfThunk)
        [ XType a tR, xThunk ]

utArgsOfThunk :: (Bound Name, Type Name)
utArgsOfThunk
 =      ( UName (NameVar "ddcArgsThunk")
        , tForall kRegion
           $ \tR -> (tPtr tR tObj `tFun` tNat))


-- | Set one of the argument pointers in a thunk.
xSetFieldOfThunk 
        :: a 
        -> Type Name    -- ^ Region containing thunk. 
        -> Type Name    -- ^ Region containigng new child.
        -> Exp a Name   -- ^ Thunk to set field of.
        -> Exp a Name   -- ^ Base offset.
        -> Exp a Name   -- ^ Index of field from base.
        -> Exp a Name   -- ^ New child value.
        -> Exp a Name

xSetFieldOfThunk a tR tC xObj xBase xIndex xVal
 = xApps a (XVar a $ fst utSetFieldOfThunk)
        [ XType a tR, XType a tC, xObj, xBase, xIndex, xVal]

utSetFieldOfThunk :: (Bound Name, Type Name)
utSetFieldOfThunk
 =      ( UName (NameVar "ddcSetThunk")
        , tForalls [kRegion, kRegion]
           $ \[tR1, tR2] 
           -> (tPtr tR1 tObj 
                        `tFun` tNat          `tFun` tNat 
                        `tFun` tPtr tR2 tObj `tFun` tVoid))


-- | Apply a thunk to some more arguments.
xApplyThunk
        :: a -> Int
        -> [Exp a Name] -> Exp a Name

xApplyThunk a arity xsArgs
 = xApps a (XVar a $ fst (utApplyThunk arity)) xsArgs

utApplyThunk :: Int -> (Bound Name, Type Name)
utApplyThunk arity
 = let  krThunk  = kRegion
        krsArg   = replicate arity kRegion
        krResult = kRegion
        ks       = [krThunk] ++ krsArg ++ [krResult]

        t       =  tForalls ks $ \rs
                -> let  (rThunk : rsMore) = rs
                        rsArg             = take arity rsMore
                        [rResult]         = drop arity rsMore
                        Just t' = tFunOfList 
                                $  [tPtr rThunk  tObj]
                                ++ [tPtr r       tObj | r <- rsArg]
                                ++ [tPtr rResult tObj]
                   in   t'

   in   ( UName (NameVar $ "ddcApply" ++ show arity)
        , t )


-- | Run a thunk.
xRunThunk 
        :: a            -- ^ Annotation.
        -> Type Name    -- ^ Region containing thunk to run.
        -> Type Name    -- ^ Region containing result object.
        -> Exp a Name   -- ^ Expression of thunk to run.
        -> Exp a Name

xRunThunk a trThunk trResult xArg
 = xApps a (XVar a $ fst utRunThunk) 
        [XType a trThunk, XType a trResult, xArg]

utRunThunk :: (Bound Name, Type Name)
utRunThunk 
 =      ( UName (NameVar $ "ddcRunThunk")
        , tForalls [kRegion, kRegion] 
                $ \[tR1, tR2] -> tPtr tR1 tObj `tFun` tPtr tR2 tObj)


-- Boxed ------------------------------------------------------------------------------------------
-- | Allocate a Boxed object.
xAllocBoxed :: a -> Type Name -> Integer -> Exp a Name -> Exp a Name
xAllocBoxed a tR tag x2
 = xApps a (XVar a $ fst utAllocBoxed)
        [ XType a tR
        , XCon a (DaConPrim (NamePrimLit (PrimLitTag tag)) tTag)
        , x2]

utAllocBoxed :: (Bound Name, Type Name)
utAllocBoxed
 =      ( UName (NameVar "ddcAllocBoxed")
        , tForall kRegion $ \r -> (tTag `tFun` tNat `tFun` tPtr r tObj))


-- | Get a field of a Boxed object.
xGetFieldOfBoxed 
        :: a 
        -> Type Name    -- ^ Prime region var of object.
        -> Type Name    -- ^ Regino of result object.
        -> Exp a Name   -- ^ Object to update.
        -> Integer      -- ^ Field index.
        -> Exp a Name

xGetFieldOfBoxed a trPrime trField x2 offset
 = xApps a (XVar a $ fst utGetFieldOfBoxed) 
        [ XType a trPrime, XType a trField
        , x2
        , xNat a offset ]

utGetFieldOfBoxed :: (Bound Name, Type Name)
utGetFieldOfBoxed 
 =      ( UName (NameVar "ddcGetBoxed")
        , tForalls [kRegion, kRegion]
                $ \[r1, r2] 
                -> tPtr r1 tObj
                        `tFun` tNat 
                        `tFun` tPtr r2 tObj)


-- | Set a field in a Boxed Object.
xSetFieldOfBoxed 
        :: a 
        -> Type Name    -- ^ Prime region var of object.
        -> Type Name    -- ^ Region of field object.
        -> Exp a Name   -- ^ Object to update.
        -> Integer      -- ^ Field index.
        -> Exp a Name   -- ^ New field value.
        -> Exp a Name

xSetFieldOfBoxed a trPrime trField x2 offset val
 = xApps a (XVar a $ fst utSetFieldOfBoxed) 
        [ XType a trPrime, XType a trField
        , x2
        , xNat a offset
        , val]

utSetFieldOfBoxed :: (Bound Name, Type Name)
utSetFieldOfBoxed 
 =      ( UName (NameVar "ddcSetBoxed")
        , tForalls [kRegion, kRegion]
            $ \[r1, t2] -> tPtr r1 tObj `tFun` tNat `tFun` tPtr t2 tObj `tFun` tVoid)


-- Raw --------------------------------------------------------------------------------------------
-- | Allocate a Raw object.
xAllocRaw :: a -> Type Name -> Integer -> Exp a Name -> Exp a Name
xAllocRaw a tR tag x2
 = xApps a (XVar a $ fst utAllocRaw)
        [ XType a tR, xTag a tag, x2]

utAllocRaw :: (Bound Name, Type Name)
utAllocRaw
 =      ( UName (NameVar "ddcAllocRaw")
        , tForall kRegion $ \r -> (tTag `tFun` tNat `tFun` tPtr r tObj))


-- | Get the payload of a Raw object.
xPayloadOfRaw :: a -> Type Name -> Exp a Name -> Exp a Name
xPayloadOfRaw a tR x2 
 = xApps a (XVar a $ fst utPayloadOfRaw) 
        [XType a tR, x2]
 
utPayloadOfRaw :: (Bound Name, Type Name)
utPayloadOfRaw
 =      ( UName (NameVar "ddcPayloadRaw")
        , tForall kRegion $ \r -> (tFun (tPtr r tObj) (tPtr r (tWord 8))))


-- Slots ------------------------------------------------------------------------------------------
-- | Allocate a pointer on the stack for a GC root.
xAllocSlot :: a -> Region Name -> Exp a Name
xAllocSlot a tR
 = XApp a (XVar a uAllocSlot) (XType a tR)

uAllocSlot :: Bound Name
uAllocSlot
 = UPrim (NamePrimOp $ PrimStore $ PrimStoreAllocSlot)
         (typeOfPrimStore PrimStoreAllocSlot)


-- | Allocate a pointer on the stack for a GC root.
xAllocSlotVal :: a -> Region Name -> Exp a Name -> Exp a Name
xAllocSlotVal a tR xVal
 = XApp a (XApp a (XVar a uAllocSlotVal) (XType a tR)) xVal

uAllocSlotVal :: Bound Name
uAllocSlotVal
 = UPrim (NamePrimOp $ PrimStore $ PrimStoreAllocSlotVal)
         (typeOfPrimStore PrimStoreAllocSlotVal)


-- Small ------------------------------------------------------------------------------------------
-- | Allocate a Small object.
xAllocSmall :: a -> Type Name -> Integer -> Exp a Name -> Exp a Name
xAllocSmall a tR tag x2
 = xApps a (XVar a $ fst utAllocSmall)
        [ XType a tR, xTag a tag, x2]


utAllocSmall :: (Bound Name, Type Name)
utAllocSmall
 =      ( UName (NameVar "ddcAllocSmall")
        , tForall kRegion $ \r -> (tTag `tFun` tNat `tFun` tPtr r tObj))


-- | Get the payload of a Small object.
xPayloadOfSmall :: a -> Type Name -> Exp a Name -> Exp a Name
xPayloadOfSmall a tR x2 
 = xApps a (XVar a $ fst utPayloadOfSmall) 
        [XType a tR, x2]
 
utPayloadOfSmall :: (Bound Name, Type Name)
utPayloadOfSmall
 =      ( UName (NameVar "ddcPayloadSmall")
        , tForall kRegion $ \r -> (tFun (tPtr r tObj) (tPtr r (tWord 8))))


-- Garbage Collector  -----------------------------------------------------------------------------

-- Initialize the runtime system.
xddcInit   :: a -> Integer -> Exp a Name
xddcInit a bytesHeap
 = xApps a (XVar a $ fst $ utddcInit)
           [ xNat a bytesHeap ]

utddcInit :: (Bound Name, Type Name)
utddcInit
 =      ( UName (NameVar "ddcInit")
        , tNat `tFun` tUnit )


-- Shutdown the runtime system and exit cleanly with the given exit code.
xddcExit   :: a -> Integer -> Exp a Name
xddcExit a code
 = xApps a (XVar a $ fst $ utddcExit)
           [ xNat a code ]

utddcExit :: (Bound Name, Type Name)
utddcExit
 =      ( UName (NameVar "ddcExit")
        , tNat `tFun` tVoid )


-- | Check if allocation is possible, if not perform garbage collection.
xAllocCollect :: a -> Exp a Name -> Exp a Name
xAllocCollect a bytes
 = XApp a (XVar a $ fst utAllocCollect) bytes

utAllocCollect :: (Bound Name, Type Name)
utAllocCollect
 =      ( UName (NameVar "allocCollect")
        , tNat `tFun` tUnit )


-- Error ------------------------------------------------------------------------------------------
-- | Get the payload of a Small object.
xErrorDefault :: a -> Exp a Name -> Exp a Name -> Exp a Name
xErrorDefault a xStr xLine
 = xApps a (XVar a $ fst utErrorDefault) 
           [xStr, xLine]
 
utErrorDefault :: (Bound Name, Type Name)
utErrorDefault
 =      ( UName (NameVar "primErrorDefault")
        , tTextLit `tFun` tNat `tFun` tPtr rTop tObj)


-- Primops ----------------------------------------------------------------------------------------
-- | Cast a pointer
xCast :: a -> Type Name -> Type Name -> Type Name -> Exp a Name -> Exp a Name
xCast a r toType fromType xPtr
 =     XApp a (XApp a (XApp a (XApp a (XVar a uCast)
                                      (XType a r)) 
                              (XType a toType))
                      (XType a fromType))
              xPtr           
                      
uCast :: Bound Name
uCast = UPrim (NamePrimOp $ PrimStore $ PrimStoreCastPtr)
              (typeOfPrimStore PrimStoreCastPtr)

