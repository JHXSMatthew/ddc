
-- | Type substitution.
module DDC.Core.Transform.SubstituteW
        ( SubstituteW(..)
        , substituteW
        , substituteWs)
where
import DDC.Core.Exp
import DDC.Core.Collect.FreeX
import DDC.Core.Collect.FreeT
-- import DDC.Core.Transform.LiftW
import DDC.Type.Compounds
import DDC.Type.Transform.SubstituteT
import Data.Maybe
import qualified DDC.Type.Env   as Env
import qualified Data.Set       as Set
import Data.Set                 (Set)


-- | Wrapper for `substituteWithW` that determines the set of free names in the
--   type being substituted, and starts with an empty binder stack.
substituteW :: (SubstituteW c, Ord n) => Bind n -> Witness n -> c n -> c n
substituteW b w xx
 | Just u       <- takeSubstBoundOfBind b
 = let  -- Determine the free names in the type we're subsituting.
        -- We'll need to rename binders with the same names as these
        fnsX    = Set.fromList
                $ mapMaybe takeNameOfBound 
                $ Set.toList 
                $ freeX Env.empty w

        fnsT    = Set.fromList
                $ mapMaybe takeNameOfBound 
                $ Set.toList 
                $ freeT Env.empty w
       
        stack    = BindStack [] [] 0 0
 
  in    substituteWithW u w fnsT fnsX stack stack xx

 | otherwise    = xx
 

-- | Wrapper for `substituteW` to substitute multiple things.
substituteWs :: (SubstituteW c, Ord n) => [(Bind n, Witness n)] -> c n -> c n
substituteWs bts x
        = foldr (uncurry substituteW) x bts


class SubstituteW (c :: * -> *) where
 -- | Substitute a witness into some thing.
 --   In the target, if we find a named binder that would capture a free variable
 --   in the type to substitute, then we rewrite that binder to anonymous form,
 --   avoiding the capture.
 substituteWithW
        :: forall n. Ord n
        => Bound n              -- ^ Bound variable that we're subsituting into.
        -> Witness n            -- ^ Witness to substitute.
        -> Set n                -- ^ Names of free spec names in the exp to substitute.
        -> Set n                -- ^ Names of free valwit names in the exp to substitute.
        -> BindStack n          -- ^ Bind stack for spec names.
        -> BindStack n          -- ^ Bind stack for valwit names.
        -> c n -> c n


-- Instances --------------------------------------------------------------------------------------
instance SubstituteW Witness where
 substituteWithW u w fnsT fnsX stackT stackX ww
  = let down    = substituteWithW u w fnsT fnsX stackT stackX
    in case ww of
        WCon{}                  -> ww
        WApp  w1 w2             -> WApp  (down w1) (down w2)
        WJoin w1 w2             -> WJoin (down w1) (down w2)
        WType{}                 -> ww

        WVar u'
         -> case substBound stackX u u' of
                Left u''  -> WVar u''
                Right _n  -> w                                                  -- TODO: liftW by n


instance SubstituteW (Exp a) where 
 substituteWithW u w fnsT fnsX stackT stackX xx
  = let down    = substituteWithW u w fnsT fnsX stackT stackX
    in case xx of
        XVar{}          -> xx
        XCon{}          -> xx
        XApp  a x1 x2   -> XApp  a   (down x1)  (down x2)

        XLAM  a b xBody
         -> let (stackT', b')   = pushBind fnsX stackX b
                xBody'          = substituteWithW u w fnsT fnsX stackT' stackX xBody
            in  XLAM  a b' xBody'

        XLam  a b xBody
         | namedBoundMatchesBind u b -> xx
         | otherwise
         -> let (stackX', b')   = pushBind fnsX stackX b
                xBody'          = substituteWithW u w fnsT fnsX stackT stackX' xBody
            in  XLam  a b' xBody'

        XLet  a (LLet m b x1) x2                        -- TODO: namedBoundMatchesBind check
         -> let m'              = down m
                (stackX', b')   = pushBind fnsX stackX b
                x1'             = down x1
                x2'             = substituteWithW u w fnsT fnsX stackT stackX' x2
            in  XLet a (LLet m' b' x1') x2'

        XLet a (LRec bxs) x2                            -- TODO: namedBoundMatchesBind checks
         -> let (bs, xs)        = unzip bxs
                (stackX', bs')  = pushBinds fnsX stackX bs
                xs'             = map (substituteWithW u w fnsT fnsX stackT stackX') xs
                x2'             = substituteWithW u w fnsT fnsX stackT stackX' x2
            in  XLet a (LRec (zip bs' xs')) x2'

        XLet a (LLetRegion b bs) x2                     -- TODO namedBoundMatchesBind checks on bs
         -> let (stackT', b')   = pushBind  fnsT stackT b
                (stackX', bs')  = pushBinds fnsX stackX bs
                x2'             = substituteWithW u w fnsT fnsX stackT' stackX' x2
            in  XLet a (LLetRegion b' bs') x2'

        XLet a (LWithRegion uR) x2
         -> XLet a (LWithRegion uR) (down x2)

        XCase a x alts  -> XCase a  (down x)   (map down alts)
        XCast a c x     -> XCast a  (down c)   (down x)
        XType{}         -> xx
        XWitness w1     -> XWitness (down w1)


instance SubstituteW LetMode where
 substituteWithW u f fnsT fnsX stackT stackX lm
  = let down = substituteWithW u f fnsT fnsX stackT stackX
    in case lm of
        LetStrict        -> lm
        LetLazy Nothing  -> LetLazy Nothing
        LetLazy (Just w) -> LetLazy (Just (down w))


instance SubstituteW (Alt a) where                      -- TODO: namedBoundMatchesBind checks on bs
 substituteWithW u f fnsT fnsX stackT stackX alt
  = let down    = substituteWithW u f fnsT fnsX stackT stackX
    in case alt of
        AAlt p x -> AAlt p (down x)


instance SubstituteW Cast where
 substituteWithW u w fnsT fnsX stackT stackX cc
  = let down    = substituteWithW u w fnsT fnsX stackT stackX 
    in case cc of
        CastWeakenEffect eff    -> CastWeakenEffect  eff
        CastWeakenClosure clo   -> CastWeakenClosure clo
        CastPurify w'           -> CastPurify (down w')
        CastForget w'           -> CastForget (down w')


