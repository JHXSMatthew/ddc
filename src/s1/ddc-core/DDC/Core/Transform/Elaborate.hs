
-- | Add possible Const and Distinct witnesses that aren't
--   otherwise in the program.
module DDC.Core.Transform.Elaborate
       ( elaborateModule
       , elaborateX )
where
import DDC.Core.Exp
import DDC.Core.Module
import DDC.Type.Exp.Simple
import DDC.Data.ListUtils
import Control.Monad
import Control.Arrow
import Data.Maybe
import Data.List


-- | Elaborate witnesses in a module.
elaborateModule :: Eq n => Module a n -> Module a n
elaborateModule mm
        = mm { moduleBody = elaborate [] $ moduleBody mm }


-- | Elaborate witnesses in an expression.
elaborateX :: Eq n => Exp a n -> Exp a n
elaborateX xx
        = elaborate [] xx


-------------------------------------------------------------------------------
class Elaborate (c :: * -> *) where
  elaborate :: Eq n => [Bound n] -> c n -> c n


instance Elaborate (Exp a) where
 elaborate us xx
  = {-# SCC elaborate #-}
    let down = elaborate us
    in case xx of
        XVar{}            -> xx
        XAbs  a b    x    -> XAbs a b (down x)
        XApp  a x1   x2   -> XApp a (down x1) (down x2)

        XLet  a lts  x2
         -> let (us', lts') = elaborateLets us lts
            in  XLet a lts' (elaborate us' x2)

        XAtom {}          -> xx
        XCase a x    alts -> XCase a (down x) (map down alts)
        XCast a cst  x2   -> XCast a (down cst) (down x2)


instance Elaborate (Arg a) where
 elaborate us aa
  = case aa of
        RType{}         -> aa
        RWitness{}      -> aa
        RTerm x         -> RTerm     (elaborate us x)
        RImplicit arg'  -> RImplicit (elaborate us arg')


instance Elaborate (Cast a) where
 elaborate _us cst = cst


instance Elaborate (Alt a) where
  elaborate us (AAlt p x) = AAlt p (elaborate us x)


-- | Elaborate witnesses in some let-bindings.
elaborateLets
        :: Eq n
        => [Bound n]            -- ^ Witness bindings in the environment.
        -> Lets a n             -- ^ Elaborate these let bindings.
        -> ([Bound n], Lets a n)

elaborateLets us lts
 = let down = elaborate us
   in case lts of
        LLet b x   -> (us, LLet b (down x))
        LRec bs    -> (us, LRec $ map (second down) bs)

        LPrivate brs mt bws
         |  urs@(_:_) <- takeSubstBoundsOfBinds brs
         -> let
                -- Mutable regions bound here.
                rsMutable       = catMaybes
                                $ map (takeMutableRegion . typeOfBind) bws

                -- Make a new const witness for all non-mutable regions.
                constWits       = map makeConstWit
                                $ urs \\ rsMutable

                -- Make a new distinct witness against all regions
                -- in the environment.
                Just ursTail    = takeTail urs
                distinctWits    = map makeDistinctWit
                                $  liftM2 (,) us   urs
                                ++ zip        urs  ursTail

            in  ( us ++ urs
                , LPrivate brs mt $ bws ++ distinctWits ++ constWits )

        _          -> (us, lts)

makeConstWit u
        = BNone $ tConst (TVar u)

makeDistinctWit (u1,u2)
        = BNone $ tDistinct 2 [TVar u1, TVar u2]

takeMutableRegion tt
 = case takeTyConApps tt of
        Just (TyConWitness TwConMutable, [TVar u]) -> Just u
        _                                          -> Nothing

