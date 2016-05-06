{-# LANGUAGE TypeFamilies, UndecidableInstances #-}

-- Generic type expression representation.
module DDC.Type.Exp.Generic.Exp where


-------------------------------------------------------------------------------
-- Type functions associated with the language definition.

-- | Yield the type of annotations for language @l@.
type family GAnnot l

-- | Yield the type of binding occurrences of variables for language @l@.
type family GBind  l

-- | Yield the type of bound occurrences of variables for language @l@.
type family GBound l

-- | Yield the type of primitive names for language @l@.
type family GPrim  l


-------------------------------------------------------------------------------
-- | Generic type expression representation.
data GType l
        -- | An annotated type.
        = TAnnot     !(GAnnot l) (GType l)

        -- | Type constructor or literal.
        | TCon       !(GCon   l)

        -- | Type variable.
        | TVar       !(GBound l)

        -- | Type abstracton.
        | TAbs       !(GBind  l) (GType l)

        -- | Type application.
        | TApp       !(GType  l) (GType l)


-------------------------------------------------------------------------------
-- | Wrapper for primitive constructors that adds the ones
--   common to SystemFω based languages.
data GCon l
        -- | The function constructor.
        = TConFun

        -- | The unit constructor.
        | TConUnit

        -- | The void constructor.
        | TConVoid

        -- | Take the least upper bound at the given kind,
        --   of the given number of elements.
        | TConSum    !(GType l) Int

        -- | The least element of the given kind.
        | TConBot    !(GType l)

        -- | The universal quantifier with a parameter of the given kind.
        | TConForall !(GType l)

        -- | The existential quantifier with a parameter of the given kind.
        | TConExists !(GType l)

        -- | Primitive constructors.
        | TConPrim   !(GPrim l)


-------------------------------------------------------------------------------
-- | Representation of the function type.
pattern TFun            = TCon TConFun

-- | Representation of the unit type.
pattern TUnit           = TCon TConUnit

-- | Representation of the void type.
pattern TVoid           = TCon TConVoid

-- | Representation of forall quantified types.
pattern TForall k b t   = TApp (TCon (TConForall k)) (TAbs b t)

-- | Representation of exists quantified types.
pattern TExists k b t   = TApp (TCon (TConExists k)) (TAbs b t)

-- | Representation of primitive type constructors.
pattern TPrim   p       = TCon (TConPrim p)


-------------------------------------------------------------------------------
-- | Synonym for show constraints of all language types.
type ShowLanguage l
        = ( Show l
          , Show (GAnnot l)
          , Show (GBind  l), Show (GBound l)
          , Show (GPrim  l))

deriving instance ShowLanguage l => Show (GType l)
deriving instance ShowLanguage l => Show (GCon  l)
