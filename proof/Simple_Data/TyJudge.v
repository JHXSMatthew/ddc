
Require Export Exp.


(** Type Judgements *************************************************)
Inductive TYPE : defs -> tyenv -> exp -> ty -> Prop :=
 (* Variables *)
 | TYVar 
   :  forall ds te i t
   ,  get te i = Some t
   -> TYPE ds te (XVar i) t

 (* Lambda Abstraction *)
 | TYLam
   :  forall ds te x t1 t2
   ,  TYPE ds (te :> t1) x            t2
   -> TYPE ds te         (XLam t1 x) (TFun t1 t2)

 (* Applications *)
 | TYApp
   :  forall ds te x1 x2 t1 t2
   ,  TYPE ds te x1           (TFun t1 t2)
   -> TYPE ds te x2           t1
   -> TYPE ds te (XApp x1 x2) t2

 (* Data Constructors *)
 | TYCon 
   :  forall ds te xs dc tsArgs tResult
   ,  getDataDef dc ds = Some (DefData dc tsArgs tResult)
   -> Forall2 (TYPE ds te) xs tsArgs
   -> TYPE ds te (XCon dc xs) tResult

 | TYCase
   :  forall ds te xObj alts tPat tResult
   ,  TYPE ds te xObj tPat
   -> (Forall (fun a => TYPEA ds te a tPat tResult) alts)
   -> TYPE ds te (XCase xObj alts) tResult

with TYPEA : defs -> tyenv -> alt -> ty -> ty -> Prop :=
 (* Case Alternatives *)
 | TYAlt 
   :  forall ds te x1 t1 dc tsArgs tResult
   ,  getDataDef dc ds = Some (DefData dc tsArgs tResult)
   -> TYPE  ds (te ++ envOfList tsArgs) x1 t1
   -> TYPEA ds te (AAlt dc x1) tResult t1.

Hint Constructors TYPE.
Hint Constructors TYPEA.


(* Well Formedness **************************************************)
(* A well typed expression is well formed *)
Theorem type_wfX
 :  forall ds te x t
 ,  TYPE ds te x t
 -> wfX te x.
Proof.
 intros ds te x t.
 gen ds te t.

 eapply 
  (exp_mutind 
    (fun x => forall ds te t,     TYPE  ds te x t     -> wfX te x) 
    (fun a => forall ds te t1 t2, TYPEA ds te a t1 t2 -> wfA te a))
 ; intros; try (inverts H).

 Case "XVar".
  eauto.

 Case "XLam".
  inverts H0. eauto.

 Case "XApp".
  inverts H1. eauto.

 Case "XCon".
  apply WfX_XCon.
  rewrite Forall_forall.
   intros. 
   inverts H0.
   lets D: Forall2_exists_left H1 H8.
    destruct D. 
    apply H in H0. eauto. eauto.

 Case "XCase".
  inverts H1.
  eapply WfX_XCase.
   eapply H. eauto.
   rewrite Forall_forall.
   rewrite Forall_forall in H8.
    eauto.

 Case "XAlt".
  inverts H0.
  eapply WfA_AAlt; eauto.
Qed.
Hint Resolve type_wfX.


(* Weakening Type Env in Type Judgement *****************************
   We can insert a new type into the type environment, provided we
   lift existing references to types higher in the stack across
   the new one.
 *)
Lemma type_tyenv_insert
 :  forall ds te ix x t1 t2
 ,  TYPE ds te x t1
 -> TYPE ds (insert ix t2 te) (liftX ix x) t1.
Proof.
 intros.
 gen ix ds te t1.

 eapply 
  (exp_mutind 
    (fun x => forall ix ds te t1
           ,  TYPE ds te x t1    
           -> TYPE ds (insert ix t2 te) (liftX ix x) t1) 
    (fun a => forall ix ds te t3 t4
           ,  TYPEA ds te a t3 t4 
           -> TYPEA ds (insert ix t2 te) (liftA ix a) t3 t4))
  ; intros; simpl.

 Case "XVar".
  inverts H.
  lift_cases; intros; auto.

 Case "XLam".
  inverts H0.
  apply TYLam.
  rewrite insert_rewind. 
   apply H. auto.

 Case "XApp".
  inverts H1.
  eapply TYApp.
   eauto. eauto.

 Case "XCon".
  inverts H0.
  eapply TYCon. 
   eauto.
   apply (Forall2_map_left (TYPE ds (insert ix t2 te))).
   apply (Forall2_impl_In (TYPE ds te)); eauto.

 Case "XCase".
  inverts H1.
  eapply TYCase. 
   eauto.
   apply Forall_map.
   eapply (Forall_impl_In (fun a => TYPEA ds te a tPat t1)); eauto.

 Case "XAlt".
  inverts H0.
  eapply TYAlt. eauto.
  assert ( insert ix t2 te ++ envOfList tsArgs 
         = insert (ix + List.length tsArgs) t2 (te ++ envOfList tsArgs)).
      admit.
  rewrite H0.
  eapply H.
Qed. 

Lemma type_tyenv_weaken
 :  forall e x t1 t2
 ,  TYPE  e         x            t1
 -> TYPE (e :> t2) (liftX 0 x) t1.
Proof.
 intros.
 assert (e :> t2 = insert 0 t2 e).
  simpl. destruct e; auto.
  rewrite H0. apply type_tyenv_insert. auto.
Qed.


