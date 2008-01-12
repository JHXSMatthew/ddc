
module Core.Optimise.Atomise
	( atomiseTree )
where

import	Core.Exp
import	Core.Plate.Walk

import	qualified Shared.Var		as Var
import	qualified Shared.VarBind	as Var

import	Util

-----
type	AtomiseM	= State ()

atomiseTree 
	:: Tree 	-- source tree
	-> Tree		-- header tree
	-> Tree

atomiseTree cSource cHeader 
 = evalState
 	(walkZM	walkTableId
		{ transX	= atomiseX }
		cSource)
	()
	
atomBinds
	= [Var.VNil, Var.VFalse, Var.VTrue]


atomiseX 
	:: WalkTable AtomiseM 
	-> Exp 
	-> AtomiseM Exp

atomiseX table xx
 	| XPrim MCall ts@[XVar v tV, _, XType (TVar KRegion r)]	
					<- xx

	, elem (Var.bind v) atomBinds
	, isConst table r
	= return $ XAtom v ts

	| XPrim MCall [XVar v tV]	<- xx
	, Var.bind v == Var.VUnit
	= return $ XAtom v []
	 
	| otherwise
	= return xx
	

isConst :: WalkTable AtomiseM -> Var -> Bool
isConst table v
--	= Debug.trace ("fs = " ++ (show $ Map.keys $ boundFs table))
	= isConst' table v

isConst' table v
	| Just fs	<- Nothing -- Map.lookup v $ boundFs table
	, or $ map (\(TClass v _) -> Var.bind v == Var.FConst) fs
	= True
	
	| otherwise
	= False
