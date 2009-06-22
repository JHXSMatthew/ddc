{-# OPTIONS -fno-warn-unused-binds #-}

module Source.Parser.Module
	( parseModule
	, run
	, pModule
	, pTopImport)

where
import Source.Parser.Pattern
import Source.Parser.Exp
import Source.Parser.Base
import Source.Parser.Type

import Source.Lexer
import Source.Pretty
import Source.Exp
import qualified Source.Token	as K

import Shared.Pretty
import qualified Shared.Var	as Var
import Shared.VarSpace		(NameSpace(..))

import qualified Text.ParserCombinators.Parsec.Prim		as Parsec
import qualified Text.ParserCombinators.Parsec.Combinator	as Parsec
import qualified Text.ParserCombinators.Parsec.Pos		as Parsec

import Util

-- | Parse a module.
parseModule :: String -> [K.TokenP] -> [Top SP]
parseModule fileName tokens
 = let	eExp	= Parsec.runParser pModule () fileName tokens
   in	case eExp of
   		Right exp	-> exp
		Left err	-> error $ show err

-- run a single parsed on some string, 
--	(for testing)
run parser str
 = let 	tokens		= scan str
 	eExp		= Parsec.runParser parser () "file" tokens
   in	case eExp of
		Right exp	-> putStr $ (pprStrPlain exp ++ "\n\n")
		Left err	-> error $ show err

-- Module ------------------------------------------------------------------------------------------
-- | Parse a whole module.
pModule :: Parser [Top SP]
pModule
 = do	tops	<- pCParen $ Parsec.sepEndBy1 pTop pSemis
	return	tops

-- | Parse a top level binding.
pTop :: Parser (Top SP)
pTop
 =
        pTopPragma
   <|>	pTopImport
   <|>  pTopExport
   <|> 	pTopForeignImport
   <|>	pTopInfix
   <|>	pTopTypeKind
   <|>	pTopTypeSynonym
   <|>	pTopData
   <|>	pTopEffect
   <|>	pTopRegion
   <|>	pTopClass
   <|>  pTopInstance
   <|>  pTopProject

 	-- SIG/BIND
   <|>	do	stmt	<- pStmt_sigBind
	 	return	$ PStmt stmt


-- Pragma ------------------------------------------------------------------------------------------
pTopPragma :: Parser (Top SP)
pTopPragma
 = do	tok	<- pTok K.Pragma
 	exps	<- Parsec.many1 pExp1
	return	$ PPragma (spTP tok) exps


-- Import ------------------------------------------------------------------------------------------
pTopImport :: Parser (Top SP)
pTopImport
 = do	-- import { MODULE ; ... }
   	tok	<- pTok K.Import
	mods	<- pCParen (Parsec.sepEndBy1 pModuleName pSemis)
	return	$ PImportModule (spTP tok) mods

pModuleName :: Parser (Var.Module)
pModuleName
 = 	
 	-- M1.M2 ..
	(Parsec.try $ do	
		mod	<- pModuleNameQual
		pTok K.Dot
		con	<- pCon
		return	$ Var.ModuleAbsolute (mod ++ [Var.name con]))

 <|>	-- M1
 	do	con	<- pCon
		return	$ Var.ModuleAbsolute [Var.name con]

-- Export -----------------------------------------------------------------------------------------
pTopExport :: Parser (Top SP)
pTopExport 
 = do	-- export { EXPORT ; .. }
	tok	<- pTok K.Export
	exps	<- pCParen (Parsec.sepEndBy1 pExport pSemis)
	return	$ PExport (spTP tok) exps

pExport :: Parser (Export SP)
pExport 
 = do	-- var
	var	<- liftM vNameV pVarCon
	return	$ EValue (spV var) var

 <|> do	-- type VAR
	tok	<- pTok K.Type
	var	<- liftM vNameT pVarCon
	return	$ EType (spTP tok) var
	
 <|> do	-- region VAR
	tok	<- pTok K.Region
	var	<- liftM vNameR pVar
	return	$ ERegion (spTP tok) var
	
 <|> do	-- effect VAR
	tok	<- pTok K.Effect
	var	<- liftM vNameE pVar
	return	$ EEffect (spTP tok) var
	
 <|> do	-- class VAR
	tok	<- pTok K.Class
	var	<- liftM vNameW pVar
	return	$ EClass (spTP tok) var

-- Foreign -----------------------------------------------------------------------------------------
-- Parse a foreign import.
pTopForeignImport :: Parser (Top SP)
pTopForeignImport
 = 	-- foreign import data STRING VAR :: KIND
  (Parsec.try $ do
	tok	<- pTok K.Foreign
	pTok K.Import
	pTok K.Data
	name	<- pString 

	con	<- liftM vNameT $ pCon
	let con2 = con { Var.info = [Var.ISeaName name] }

	pTok K.HasType
	kind	<- pKind
			
	return	$ PForeign (spTP tok) (OImportUnboxedData name con2 kind))
	
	-- foreign import data STRING VAR
 <|> (Parsec.try $ do
	tok	<- pTok K.Foreign
	pTok K.Import
	pTok K.Data
	name	<- pString 

	con	<- liftM vNameT $ pCon
	let con2 = con { Var.info = [Var.ISeaName name] }

	return	$ PForeign (spTP tok) (OImportUnboxedData name con2 KValue))
	
 <|> do	-- foreign import STRING var :: TYPE
	tok	<- pTok K.Foreign
 	pTok K.Import

	mExName	<-  liftM Just pString 
		<|> return Nothing

	var	<- pVar

	pTok K.HasType
	sig	<- pType

	mOpType	<-  liftM Just 
			(do 	pTok K.HasOpType
				pTypeOp)
		<|> return Nothing
		
	return	$ PForeign (spTP tok) $ OImport mExName (vNameV var) sig mOpType


-- Infix -------------------------------------------------------------------------------------------
-- Parse an infix definition.
pTopInfix :: Parser (Top SP)
pTopInfix
 = 	-- infixr INT SYM ..
 	do	tok	<- pTok K.InfixR
 		prec	<- pInt
		syms	<- liftM (map vNameV) $ Parsec.sepBy1 pSymbol (pTok K.Comma)
		return	$ PInfix (spTP tok) InfixRight prec syms

	-- infixl INT SYM .. 
  <|> 	do	tok	<- pTok K.InfixL
 		prec	<- pInt
		syms	<- liftM (map vNameV) $ Parsec.sepBy1 pSymbol (pTok K.Comma)
		return	$ PInfix (spTP tok) InfixLeft prec syms

  <|>	-- infix INT SYM ..
  	do	tok	<- pTok K.Infix
		prec	<- pInt
		syms	<- liftM (map vNameV) $ Parsec.sepBy1 pSymbol (pTok K.Comma)
		return	$ PInfix (spTP tok) InfixNone prec syms


-- Type Kind ---------------------------------------------------------------------------------------
-- | Parse a type kind signature.
pTopTypeKind :: Parser (Top SP)
pTopTypeKind 
 = 	-- type CON :: KIND
 	Parsec.try $ do	
		tok	<- pTok K.Type
		con	<- liftM vNameT pCon
		pTok	K.HasType
		kind	<- pKind
		return	$ PTypeKind (spTP tok) con kind
		

-- Type Synonym ------------------------------------------------------------------------------------
-- | Parse a type synonym.
pTopTypeSynonym :: Parser (Top SP)
pTopTypeSynonym
 = 	-- type VAR :: TYPE
 	Parsec.try $ do	
		tok	<- pTok K.Type
		var	<- liftM vNameT pVar
		pTok	K.HasType
		t	<- pType
		return	$ PTypeSynonym (spTP tok) var t


-- Effect ------------------------------------------------------------------------------------------
-- | Parse an effect definition.
pTopEffect :: Parser (Top SP)
pTopEffect
 =	-- effect CON :: KIND
 	do	tok	<- pTok K.Effect
		con	<- pCon
		pTok	K.HasType
		kind	<- pKind
		return	$ PEffect (spTP tok) (vNameE con) kind
		

-- Region ------------------------------------------------------------------------------------------
-- | Parse a region definition
pTopRegion :: Parser (Top SP)
pTopRegion
 = 	-- region var
 	do	tok	<- pTok K.Region
		var	<- pVar
		return	$ PRegion (spTP tok) (vNameR var)
		

-- Data --------------------------------------------------------------------------------------------
-- | Parse a data type definition.
pTopData :: Parser (Top SP)
pTopData
 = 
 	-- data TYPE = CTOR | .. 
  	do	tok	<- pTok	K.Data
		con	<- liftM vNameT $ pCon
		vars	<- liftM (map (vNameDefaultN NameType)) $ Parsec.many pVar
	
		ctors	<- 	(Parsec.try $ do
					pTok K.Equals
					ctors	<- Parsec.sepBy1 pTopData_ctor (pTok K.Bar)
					return	ctors)
			   <|>	return []
	
		return	$ PData (spTP tok) con vars ctors

pTopData_ctor :: Parser (Var, [DataField (Exp SP) Type])
pTopData_ctor
 = 	-- CON { FIELD ; .. }
	-- overlaps with CON TYPES ..
 	(Parsec.try $ do
		con	<- liftM vNameT pCon
		fs	<- pCParen $ Parsec.sepEndBy1 pDataField pSemis
		return	(con, fs))
		
 
 	-- CON TYPES ..
 <|> 	do	con	<- liftM vNameT pCon
		types	<- Parsec.many pType_body1

		let mkPrimary typ
			= DataField
			{ dPrimary	= True
			, dLabel	= Nothing
			, dType		= typ
			, dInit		= Nothing }

		return	(con, map mkPrimary types)
 	
pDataField :: Parser (DataField (Exp SP) Type)
pDataField
 =  	-- .VAR :: TYPE = EXP
 	do	pTok K.Dot
		var	<- liftM vNameF pVar
		pTok K.HasType
		t	<- pType_body
		pTok K.Equals
		exp	<- pExp
		return	$ DataField
			{ dPrimary	= False
			, dLabel	= Just var
			, dType		= t
			, dInit		= Just exp }
 	
	-- VAR :: TYPE
  <|>	(Parsec.try $ do	
  		var	<- liftM vNameF pVar
	 	pTok K.HasType
		t	<- pType_body

		return	$ DataField
			{ dPrimary	= True
			, dLabel	= Just var
			, dType		= t
			, dInit		= Nothing })

  <|>	do	t	<- pType_body
  		return	$ DataField
			{ dPrimary	= True
			, dLabel	= Nothing
			, dType		= t
			, dInit		= Nothing }

  

-- Class -------------------------------------------------------------------------------------------
-- | Parse a class definition.
pTopClass :: Parser (Top SP)
pTopClass
 =  	-- class CON :: KIND
	(Parsec.try $ do
		tok	<- pTok K.Class
	 	con	<- pCon
		pTok K.HasType
		kind	<- pKind
		return	$ PClass (spTP tok) (vNameW con) kind)

 <|>	-- class CON VAR.. where { SIG ; .. }
	do	tok	<- pTok K.Class
		con	<- liftM vNameW $ pCon
		vks	<- Parsec.many pVarKind
		pTok K.Where
		sigs	<- pCParen $ Parsec.sepEndBy1 pTopClass_sig pSemis

		return	$ PClassDict (spTP tok) con vks [] sigs

-- parse a var with optional kind
pVarKind :: Parser (Var, Kind)
pVarKind 
 = 	-- (VAR :: KIND)
	(pRParen $ do	
		var	<- liftM (vNameDefaultN NameType) pVar
		pTok K.HasType
		kind	<- pKind
		return	(var, kind))

	-- VAR
 <|>	do	var	<- liftM (vNameDefaultN NameType) pVar
		return	(var, KNil)




-- VAR, .. :: TYPE
pTopClass_sig :: Parser ([Var], Type)
pTopClass_sig
 = do	vars	<- Parsec.sepBy1 pVar (pTok K.Comma)
 	pTok K.HasType
	t	<- pType
	return	$ (vars, t)
 

-- Instance ----------------------------------------------------------------------------------------
-- | Parse a class instance.
pTopInstance :: Parser (Top SP)
pTopInstance
 = 	-- instance CON TYPE .. where { BIND ; .. }
 	do	tok	<- pTok K.Instance
		con	<- liftM vNameW $ pQualified pCon
		ts	<- Parsec.many pType_body1
		pTok K.Where
		binds	<- pCParen $ Parsec.sepEndBy1 pStmt_bind pSemis
		return	$ PClassInst (spTP tok) con ts [] binds


-- Project -----------------------------------------------------------------------------------------
-- | Parse a projection definition.
pTopProject :: Parser (Top SP)
pTopProject
 = 	-- project CON TYPE .. where { SIG/BIND ; .. }
 	(Parsec.try $ do	
		tok	<- pTok K.Project
		con	<- liftM vNameT $ pQualified pCon
		ts	<- Parsec.many pType_body1
		pTok	K.Where
		binds	<- pCParen $ Parsec.sepEndBy1 pStmt_sigBind pSemis
		return	$ PProjDict (spTP tok) (TData KNil con ts) binds)

  	-- project CON TYPE .. with { VAR ; .. }
  <|>	do	tok	<- pTok K.Project
		con	<- liftM vNameT $ pQualified pCon
		ts	<- Parsec.many pType_body1
		pTok	K.With
		binds	<- pCParen $ Parsec.sepEndBy1 pTopProject_pun pSemis
		return	$ PProjDict (spTP tok) (TData KNil con ts) binds
		
pTopProject_pun :: Parser (Stmt SP)
pTopProject_pun
 = do	-- VAR
	var	<- pVar
 	return	$ SBindFun (spV var) (vNameF var)[] [ADefault (spV var) (XVar (spV var) var)]
	
	
 



