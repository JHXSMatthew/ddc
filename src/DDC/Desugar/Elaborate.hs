{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}

-- | Elaborate data type definitions and type signatures in this tree.
--   In the source program we allow region, effect, and closure infomation to be elided
--   from data type definitions and type signatures.
-- 
--   For data type definitions, we add region effect and closure parameters using heuristics
--   based on how the data constructors are defined.
--
--   In type signatures we add fresh variables to data type constructor applications,
--   using the kind of the data type constructors as a guide. These varaiables are just 
--   place holders, don't constrain the type, and just turn into 'meta' variables during
--   type inference.
--
--   NOTE: At the moment this only elaborates the effect and closure information 
--         in type signatures. It runs after Desugar.Kinds which adds in missing region variables.

--   TODO: This is fairly ad-hoc at the moment, we'll need more experience with it to
--         determine if these heuristics are what we actually want. In all cases the 
--         program should work if you add in all the required type information manually.
--
--   TODO: I expect we'll want to combine kind inference with this process in the long run.
-- 
module DDC.Desugar.Elaborate 
	(elaborateTree)
where
import Source.Error
import DDC.Desugar.Transform
import DDC.Desugar.Elaborate.EffClo
import DDC.Desugar.Elaborate.Constraint
import DDC.Desugar.Elaborate.Regions
import DDC.Desugar.Elaborate.Slurp
import DDC.Desugar.Elaborate.State
import DDC.Desugar.Glob
import DDC.Desugar.Exp
import DDC.Type.Data.Elaborate
import DDC.Type.Data
import DDC.Type
import DDC.Var
import DDC.Base.SourcePos
import DDC.Main.Error
import DDC.Main.Pretty
import Data.Sequence			(Seq)
import Data.Map				(Map)
import qualified DDC.Type.Transform	as T
import qualified Data.Sequence		as Seq
import qualified Data.Map		as Map
import Data.Traversable			(mapM)
import Prelude				hiding (mapM)
import Control.Monad.State.Strict	hiding (mapM)
import Data.Maybe

stage = "DDC.Desugar.Elaborate"

-- | Elaborate types in this tree.
elaborateTree 
	:: String		-- ^ Unique
	-> Glob SourcePos	-- ^ Header tree
	-> Glob SourcePos	-- ^ Module tree
	-> ( Glob SourcePos 	-- new header tree
	   , Glob SourcePos	-- new module tree
	   , Seq Constraint	-- the kind constaints
	   , Map Var Kind	-- the kind of every type constructor
	   , [Error])		-- errors found during elaboration

elaborateTree unique dgHeader dgModule
 = let
	((dgHeader', dgModule', constraints), state')
		= runState
			(elaborateTreeM dgHeader dgModule)
			(stateInit unique)
	
   in	( dgHeader'
	, dgModule'
	, constraints
	, stateKinds state'
	, [] )
		
elaborateTreeM dgHeader dgModule
 = do	
	-- Slurp out kind constraints from the program
 	let constraints	=      slurpConstraints dgHeader
			Seq.>< slurpConstraints dgModule

	-- Solve kind constraints
	solveConstraints constraints

	-- Update the kinds of all the type consructors
	-- TODO: huh? shouldn't this come after the next step?
	dgHeader_tagged	<- tagKindsInGlob dgHeader
	dgModule_tagged	<- tagKindsInGlob dgModule

	-- Elaborate data type definitions
	-- TODO: this probably needs to be merged with kind inference when it's ready
	-- TODO: the unpacking and repacking here is really horrible.
	let anHeader	= [ an | PData an _ <- Map.elems $ globDataDecls dgHeader_tagged]
	let anModule	= [ an | PData an _ <- Map.elems $ globDataDecls dgModule_tagged]

	let defsHeader	= fmap topDataDef $ globDataDecls dgHeader_tagged
	let defsModule	= fmap topDataDef $ globDataDecls dgModule_tagged

	(defsHeader', defsModule') 
		<- elaborateDataDefs newVarN defsHeader defsModule
				
	let makeAnDefs glob anns defs
		= glob { globDataDecls = Map.fromList 
			[ (dataDefName def, PData an def) 
				| (an, def) <- zip anns (Map.elems defs) ] }

	let dgHeader_data = makeAnDefs dgHeader_tagged anHeader defsHeader'
	let dgModule_data = makeAnDefs dgModule_tagged anModule defsModule'


	-- Now that we know what the kinds of all the type constructors are,
	-- add missing reigon variables to type signatures.
	dgHeader_rs	<- elabRegionsInGlob dgHeader_data
	dgModule_rs	<- elabRegionsInGlob dgModule_data

	-- Elaborate effects and closures
	dgHeader_effclo	<- elaborateEffCloInGlob dgHeader_rs
	dgModule_effclo	<- elaborateEffCloInGlob dgModule_rs

	-- Attach data defs
	-- TODO: merge tagkinds above with this phase to save another walk over the code.
	let defsAll		= Map.union defsHeader' defsModule'
	let dgHeader_attach	= attachDataDefsToTyConsInGlob defsAll dgHeader_effclo
	let dgModule_attach	= attachDataDefsToTyConsInGlob defsAll dgModule_effclo
	
	return	( dgHeader_attach
		, dgModule_attach
		, constraints)


-- Tag Kinds --------------------------------------------------------------------------------------
-- Tag each data constructor with its kind from this table
tagKindsInGlob :: Glob SourcePos -> ElabM (Glob SourcePos)
tagKindsInGlob pp
	= transZM (transTableId return)
		{ transT	= tagKindsT Map.empty }
		pp
		
tagKindsT :: Map Var Kind -> Type -> ElabM Type
tagKindsT local tt
 	| TVar _ (UVar v)	<- tt
	= do	kindMap	<- gets stateKinds 
		case listToMaybe $ catMaybes [Map.lookup v kindMap, Map.lookup v local] of
			Nothing	-> return $ tt
			Just k'	-> return $ TVar k' $ UVar v

	| TCon (TyConData v _ mDef) <- tt
	= do	kindMap	<- gets stateKinds
		case listToMaybe $ catMaybes [Map.lookup v kindMap, Map.lookup v local] of
			Nothing	-> return tt
			Just k'	-> return $ TCon (TyConData v k' mDef)

	| TCon{}		<- tt
	= return tt
			
	| TSum k ts		<- tt
	= do	ts'	<- mapM (tagKindsT local) ts
		return	$ TSum k ts'
	
	| TApp t1 t2		<- tt
	= liftM2 TApp (tagKindsT local t1) (tagKindsT local t2)
	
	| TForall b k t <- tt
	, Just v	<- takeVarOfBind b
	= do	let local'	= Map.insert v k local
		t'		<- tagKindsT local' t
		return		$ TForall b k t'

	| TForall b k t <- tt
	= do	t'		<- tagKindsT local t
		return		$ TForall b k t'

	| TConstrain t crs	<- tt
	= do	t'	<- tagKindsT local t
		crs'	<- tagKindsCrs local crs
		return	$ TConstrain t' crs'
		
	| otherwise
	= panic stage $ "tagKindsT: no match for " % tt
		
tagKindsCrs :: Map Var Kind -> Constraints -> ElabM Constraints
tagKindsCrs local crs
 = do	eqs'	<- mapM (tagKindsT local) $ crsEq   crs
	mores'	<- mapM (tagKindsT local) $ crsMore crs
	return	$ Constraints eqs' mores' (crsOther crs)
	

-- Attach -----------------------------------------------------------------------------------------
-- | Attach DataDefs to all TyCons in a glob.
--   This makes it easy to get the def when consuming the type.
--
attachDataDefsToTyConsInGlob :: Map Var DataDef -> Glob SourcePos -> Glob SourcePos
attachDataDefsToTyConsInGlob defs glob
	= transZ (transTableId return)
		{ transT	= \t -> return $ T.transformT (attachDataDefsT defs) t }
		glob


attachDataDefsT :: Map Var DataDef -> Type -> Type
attachDataDefsT defs tt
	| TCon (TyConData v k Nothing)	<- tt
	, Just def			<- Map.lookup v defs
	= TCon (TyConData v k (Just def))
	
	| otherwise
	= tt


-- EffClo -----------------------------------------------------------------------------------------
-- | Elaborate effects and closures in a top level signature.
elaborateEffCloInGlob :: Glob SourcePos -> ElabM (Glob SourcePos)
elaborateEffCloInGlob glob
 = do	externs'	<- mapM elaborateEffCloP (globExterns glob)
	typesigs'	<- mapM elaborateEffCloP (globTypeSigs glob)
	return	$ glob 	{ globExterns	= externs' 
			, globTypeSigs	= typesigs' }

elaborateEffCloP :: Top SourcePos -> ElabM (Top SourcePos)
elaborateEffCloP pp
  = case pp of
	PExtern sp v t mt
	 -> do	t'	<- elaborateEffCloInFunSigT t
		return	$ PExtern sp v t' mt
		
	PTypeSig a vs t
	 -> do	t'	<- elaborateEffCloInFunSigT t
		return	$ PTypeSig a vs t'
	
	_ -> return pp


