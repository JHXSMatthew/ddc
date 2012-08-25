module DDC.Core.Transform.DeadCode
    ( deadCode )
where
import DDC.Base.Pretty
import DDC.Core.Analysis.Usage
import DDC.Core.Check.CheckExp
import DDC.Core.Exp
import DDC.Type.Env
import DDC.Core.Fragment.Profile
import DDC.Core.Simplifier.Base
import DDC.Core.Transform.Reannotate
import DDC.Core.Transform.TransformX
import qualified Data.Map       as Map
import qualified Data.Set       as Set
import Control.Monad.Writer	(Writer, runWriter, tell)
import Data.Monoid		(Monoid, mempty, mappend)
import Data.Typeable		(Typeable)
import qualified DDC.Core.Collect			as C
import qualified DDC.Type.Compounds			as T
import qualified DDC.Type.Env				as T
import qualified DDC.Type.Sum				as TS
import qualified DDC.Type.Transform.Crush		as T

deadCode
	:: (Show a, Show n, Ord n, Pretty n)
	=> Profile n
	-> Env n		-- ^ Kind env
	-> Env n		-- ^ Type env
	-> Exp a n
	-> TransformResult (Exp a n)
deadCode profile kenv tenv xx
 = let (xx',info)
           = transformTypeUsage profile kenv tenv
	     (transformUpMX deadCodeTrans kenv tenv)
	     xx
   in TransformResult
	{ result	     = xx'
	, resultProgress = progress info
	, resultInfo     = TransformInfo info }
 where
  progress (DeadCodeInfo r) = r > 0


transformTypeUsage profile kenv tenv trans xx
 | Right (xx1,_,_,_) <- checkExp (configOfProfile profile) kenv tenv xx
 , (_,xx2)	     <- usageX xx1
 , (x', info)	     <- runWriter (trans xx2)
 , x''		     <- reannotate (\(_, AnTEC { annotTail = a}) -> a) x'
 = (x'', info)

 -- TODO: There was an error typechecking
 | otherwise
 = error "Unable to typecheck!?"



type Annot a n = (UsedMap n, AnTEC a n)


deadCodeTrans
	:: (Show a, Show n, Ord n, Pretty n)
	=> Env n
	-> Env n
	-> Exp (Annot a n) n
	-> Writer DeadCodeInfo (Exp (Annot a n) n)
deadCodeTrans _ _ xx
 = case xx of
    XLet a@(UsedMap um, antec) (LLet _mode b x1) x2
     | isUnused b um
     , isDead   $ annotEffect antec
     -> do
	tell mempty{infoRemoved = 1}
	return $
	    XCast a (CastWeakenEffect $ annotEffect antec)
	  $ XCast a (weakClo a x1)
	  $ x2

    _ -> return xx

 where
    weakClo a x1 = CastWeakenClosure $
		 (map (XType . TVar)
		 $ Set.toList
		 $ C.freeT T.empty x1)
	    ++   (map (XVar a)
		 $ Set.toList
		 $ C.freeX T.empty x1)

    sumList (TSum ts) = TS.toList ts
    sumList tt	      = [tt]


    isUnused (BName n _) um
     = case Map.lookup n um of
	Just [UsedNone] -> True
	Nothing		-> True
	_		-> False

    isUnused (BNone _) _ = True
    isUnused _	   _     = False

    isDead eff = all ok (map T.takeTApps $ sumList $ T.crushEffect eff)
    ok (c:_args)
     = case c of
	TCon (TyConSpec TcConAlloc)	-> True
	TCon (TyConSpec TcConDeepAlloc) -> True
	TCon (TyConSpec TcConRead)      -> True
	TCon (TyConSpec TcConHeadRead)  -> True
	TCon (TyConSpec TcConDeepRead)  -> True
	-- writes are bad, variables are bad
	_				-> False

    ok [] = False


-- | Summary
data DeadCodeInfo
    = DeadCodeInfo
    { infoRemoved  :: Int }
    deriving Typeable


instance Pretty DeadCodeInfo where
 ppr (DeadCodeInfo remo)
  =  text "DeadCode:"
  <$> indent 4 (vcat
      [ text "Removed:        "	<> int remo])


instance Monoid DeadCodeInfo where
 mempty = DeadCodeInfo 0
 mappend (DeadCodeInfo r1)
	 (DeadCodeInfo r2)
  = DeadCodeInfo (r1+r2)
