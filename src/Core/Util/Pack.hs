
module Core.Util.Pack
	( packT 
	, packK
	, flattenT 
	, inlineTWheresT
	, inlineTWheresMapT )
where
	
-----
import Core.Exp
import Core.Plate.Trans
import Core.Plate.FreeVars
import Core.Util.Effect
import Core.Util.Bits

import Shared.Error
import Shared.VarUtil
import Shared.VarPrim
import Util
import Util.Graph.Deps

import qualified Data.Map	as Map
import Data.Map			(Map)

import qualified Data.Set	as Set

-----
stage	= "Core.Util.Pack"



-- | Pack a type into standard form.
packT :: Type -> Type
packT tt
 = {-# SCC "packT" #-}
   let tt'	= packT1 tt
   in  if tt == tt'
   	then tt'
	else packT1 tt'

-- | Pack a kind into standard form.
packK :: Kind -> Kind
packK kk
 = let kk'	= packK1 kk
   in  if kk == kk'
   	then kk'
	else packK1 kk'


-- | Flatten a type so that all where bindings are inlined
flattenT :: Type -> Type
flattenT tt
 = {-# SCC "flattenT" #-}
    packT $ crushEffsT $ inlineTWheresT tt

	
 
-- | Do one round of packing
packT1 :: Type -> Type
packT1 tt 
 = case tt of
	-- push foralls under closure tags
	TForall v1 k1 (TFree v2 t2)
	 -> let t2'	= packT1 t2
	    in	TFree v2 (TForall v1 k1 t2')

 	TForall v k1 t2
	 -> let	t2'	= packT1 t2
	    in	TForall v k1 t2'

	 
	TContext k1 t2
	 -> let	k1'	= packK1 k1
	 	t2'	= packT1 t2
	    in 	TContext k1' t2'

	TFetters (TVar k v1) [FWhere v2 t2]
	 | v1 == v2
	 -> t2
	 
	TFetters t1 fs
	 -> let t1'	= packT1 t1
	 	fs'	= restrictBinds t1' fs
	    in	makeTFetters t1' fs'

	TApp t1 t2
	 -> let	t1'	= packT1 t1
	 	t2'	= packT1 t2
	    in	TApp t1' t2'
	    
	TSum k ts
	 -> makeTSum k $ nub $ map packT1 ts
	 
	-- mask
	TMask k (TBot k1) t2
	 	| k == k1
		-> TBot k1
	 
	TMask k t1 t2
	 -> let t1'	= packT1 t1
	 	t2'	= packT1 t2
	    in	applyTMask $ TMask k t1' t2'
	    
	TVar k v	-> tt
	TBot k		-> tt
	TTop k 		-> tt
	 
	-- data
	TData v ts
	 -> let	ts2	= map packT1 ts

		-- lift fetters above args
		(ts3, fss)	
			= unzip
			$ map slurpTFetters ts2

	    in	makeTFetters (TData v ts3) (concat fss)
	    
	TFunEC t1 t2 eff clo
	 -> let (t1',  fs1)	= slurpTFetters $ packT1 t1
	  	(t2',  fs2)	= slurpTFetters $ packT1 t2
		(eff', fsE)	= slurpTFetters $ packT1 eff
		(clo', fsC)	= slurpTFetters $ packT1 clo

	    in	makeTFetters (TFunEC t1' t2' eff' clo')
	    		(fs1 ++ fs2 ++ fsE ++ fsC)
	    
	TFun t1 t2
	 -> let	t1'	= packT1 t1
	 	t2'	= packT1 t2
	    in	TFun t1' t2'
	    
	-- effect
	-- crush EReadH on the way
	TEffect v [TData vD (TVar KRegion r : ts)]
	 | v == primReadH
	 -> TEffect primRead [TVar KRegion r]
	
	TEffect v [TData vD []]
	 | v == primReadH
	 -> TBot KEffect

	TEffect v ts
	 -> let	ts'	= map packT1 ts
	    in	TEffect v ts'
	    
	-- closure
	TFree v (TBot KClosure)
	 -> TBot KClosure

	TFree v1 (TFree v2 t2)
	 -> TFree v1 t2

	TFree v1 (TSum KClosure ts)
	 -> TSum KClosure (map (TFree v1) ts)

	TFree v t1
	 -> let t1'	= packT1 t1
	    in	TFree v t1'
	    
	TTag v	-> tt
	
	-- class
	-- crush LazyH on the way
	TClass v [TData vD (TVar KRegion r : ts)]
	 | v == primLazyH
	 -> TClass primLazy [TVar KRegion r]

	-- crush MutableT on the way
	TClass v [t@(TData{})]
	 | v == primMutableT
	 -> let	(rs, ds)	= slurpVarsRD t
	    in TWitJoin 
	    	$ (   map (\r -> TClass primMutable  [r]) rs
		   ++ map (\d -> TClass primMutableT [d]) ds)

	TClass v ts
	 -> let	ts'	= map packT1 ts
	    in	TClass v ts'
	
	TWitJoin ts
	 -> makeTWitJoin (map packT1 ts)
	
	-- wildcards
	TWild{}	-> tt

	_ -> panic stage
		$ "packT: no match for " % tt


slurpTFetters (TFetters t fs)	= (t, fs)
slurpTFetters tt		= (tt, [])


-- | Do one round of packing on this kind
packK1 :: Kind -> Kind
packK1 kk
 = case kk of
	-- crush LazyH on the way
	KClass v [TData vD (TVar KRegion r : ts)]
	 | v == primLazyH
	 -> KClass primLazy [TVar KRegion r]
	
	-- crush MutableT on the way
	KClass v [t@(TData{})]
	 | v == primMutableT
	 -> let	(rs, ds)	= slurpVarsRD t
	    in makeKWitJoin 
	    	$ (   map (\r -> KClass primMutable  [r]) rs
		   ++ map (\d -> KClass primMutableT [d]) ds)
		

 	KClass v ts
	 -> let	ts'	= map packT1 ts
	    in	KClass v ts'


	    
	_ -> kk



-----
-- inlineTWheresT
--	Inline all TLet expressions in this type.
--	
inlineTWheresT :: Type -> Type
inlineTWheresT tt
 = inlineTWheresMapT Map.empty Set.empty tt

inlineTWheresMapT sub block tt
 = let down	= inlineTWheresMapT sub block
   in  case tt of
 	TNil			-> tt
	
	TForall v k t		-> TForall v k (down t)
	    
	TFetters t1 fs
	 -> let	([fsWhere, fsMore], [])
	 		= partitionFs [(=@=) FWhere{}, (=@=) FMore{}] fs
		
		sub'	= Map.union 
				(Map.fromList [(v, t) | FWhere v t <- fsWhere])
				sub
				
				
	    	tFlat	= inlineTWheresMapT 
				sub'
				block
				t1

	    in	makeTFetters tFlat fsMore


	TContext l t		-> TContext l 	(down t)
	TSum     k ts		-> TSum  k 	(map down ts)
	TMask k t1 t2		-> TMask k 	(down t1) (down t2)
	    
	TVar k v	
	 -- If this var is in our block set then we're trying to recursively
	 --	substitute for it.. bail out now or we'll loop forever.
	 |  Set.member v block
	 -> tt

	 -- Lookup the var and add it to the block list so we can detect loops
	 --	in the type.
	 | otherwise
	 -> case Map.lookup v sub of
	 	Just t	-> inlineTWheresMapT sub (Set.insert v block) t
		_	-> tt
		
    	TTop k			-> tt
	TBot k			-> tt
    
	-- data
	TFunEC t1 t2 eff clo	-> TFunEC	(down t1) (down t2) (down eff) (down clo)
	TData v ts		-> TData v 	(map down ts)
	
	-- effect
	TEffect  v ts		-> TEffect v 	(map down ts)
 	
	-- closure
	TFree v t		-> TFree v 	(down t)
	TTag v			-> tt

	-- class
	TClass v ts		-> TClass v 	(map down ts)

	TWild k			-> tt
	    


-- | Restrict the list of FWhere fetters to ones which are 
--	reachable from this type. Also erase x = Bot fetters.
--
restrictBinds :: Type -> [Fetter] -> [Fetter]
restrictBinds tt ls
 = let	splitFetter ff
  	 = case ff of
	 	FWhere v t	-> (v, t)
		FMore  v t	-> (v, t)

 	reachFLetsMap
 		= Map.fromList
		$ [(t, freeVars tLet)	
 			| (t, tLet)	<- map splitFetter ls]
 
 	vsSeed		= freeVars tt

	vsReachable	= vsSeed `Set.union` graphReachableS reachFLetsMap vsSeed
	 
   in	filter	(\f -> Set.member (varOfFetter f) vsReachable)
   		ls

