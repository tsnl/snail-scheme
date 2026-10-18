(** Proofs over Ott's generated syntax and relations. *)
From Stdlib Require Import List.
From LofiSpec Require Import Lofi.
Import ListNotations.

(** Extending the surrounding type-variable scope preserves formation. *)
Scheme wf_type_mut := Induction for wf_type Sort Prop
with wf_types_mut := Induction for wf_types Sort Prop.
Combined Scheme formation_ind from wf_type_mut, wf_types_mut.

Lemma formation_weakening :
  (forall ds scope t, wf_type ds scope t ->
    forall larger, incl scope larger -> wf_type ds larger t) /\
  (forall ds scope ts, wf_types ds scope ts ->
    forall larger, incl scope larger -> wf_types ds larger ts).
Proof.
  apply formation_ind; intros; eauto using wf_type, wf_types.
Qed.

(** Every variable occurrence, including nested arguments, is in scope. *)
Lemma formation_scope :
  (forall ds scope t, wf_type ds scope t ->
    forall a, occurs_type a t -> In a scope) /\
  (forall ds scope ts, wf_types ds scope ts ->
    forall a, occurs_types a ts -> In a scope).
Proof.
  apply formation_ind; intros; match goal with
  | H : occurs_type _ _ |- _ => inversion H; subst
  | H : occurs_types _ _ |- _ => inversion H; subst
  end; eauto.
Qed.

Theorem instance_head_closed : forall ds cs c args,
  wf_instance_head ds cs (Q_class c args) ->
  forall a, ~ occurs_types a args.
Proof.
  intros ds cs c args H a Occ.
  inversion H as [ds' cs' q Head]; subst.
  inversion Head as [args' ds' cs' scope c' Arity Arguments]; subst.
  exact ((proj2 formation_scope) ds [] args Arguments a Occ).
Qed.

(** Arity comes from a visible declaration, including zero-argument names. *)
Theorem datatype_application_arity : forall ds scope d t args,
  wf_type ds scope (T_nominal d t args) ->
  ds d = Some (length (t :: args)).
Proof. intros; inversion H; assumption. Qed.

Theorem bare_datatype_arity : forall ds scope d,
  wf_type ds scope (T_nominal_zero d) -> ds d = Some 0.
Proof. intros; inversion H; assumption. Qed.

Theorem requirement_arity : forall ds cs scope c args,
  wf_requirement ds cs scope (Q_class c args) ->
  cs c = Some (length args).
Proof. intros; inversion H; assumption. Qed.

(** Omitting requirements is the same as an empty requires clause. *)
Theorem omitted_requires_agree : forall ds cs scope vars t,
  wf_signature ds cs scope (S_all vars t) <->
  wf_signature ds cs scope (S_requires vars [] t).
Proof.
  split; intros H; inversion H; subst; constructor;
    auto using WF_requirements_nil.
Qed.

(** Examples and rejected forms. Names are tagged, disjoint identity supplies. *)
Definition example_variable := TypeId 0.
Definition example_class := ClassId 0.
Definition example_datatype := DataId 0.
Definition example_type := T_variable example_variable.
Definition no_datatypes : datatype_scope := fun _ => None.
Definition no_classes : class_scope := fun _ => None.
Definition unary_datatype : datatype_scope :=
  fun d => match d with DataId 0 => Some 1 | _ => None end.
Definition unary_class : class_scope :=
  fun c => match c with ClassId 0 => Some 1 | _ => None end.

Example render_signature :
  wf_signature no_datatypes unary_class []
    (S_requires [example_variable] [Q_class example_class [example_type]]
      (T_function (F_fixed [example_type] (T_primitive P_string)))).
Proof.
  repeat constructor; simpl; auto.
Qed.

Example nested_closed_instance :
  wf_instance_head unary_datatype unary_class
    (Q_class example_class
      [T_nominal example_datatype (T_vector (T_primitive P_i32)) []]).
Proof. repeat constructor; simpl; auto. Qed.

Example wrong_requirement_arity :
  ~ wf_requirement no_datatypes unary_class [] (Q_class example_class []).
Proof.
  intro H. apply requirement_arity in H. simpl in H; intuition discriminate.
Qed.

Example open_instance_rejected :
  ~ wf_instance_head no_datatypes unary_class
    (Q_class example_class [T_vector example_type]).
Proof.
  intro H. eapply instance_head_closed; [exact H |].
  repeat constructor.
Qed.

Example unbound_variable_rejected : ~ wf_type no_datatypes [] example_type.
Proof. intro H; inversion H; assumption. Qed.

Example repeated_binder_rejected :
  ~ wf_signature no_datatypes no_classes []
      (S_all [example_variable; example_variable] example_type).
Proof.
  intro H; inversion H; subst.
  match goal with ND : NoDup (_ :: _ :: _) |- _ => inversion ND; subst end.
  simpl in *; intuition.
Qed.

Fail Check (T_ref (S_all [example_variable] example_type)).
Fail Check (T_ref (Q_class example_class [example_type])).
Fail Check (T_nominal_zero example_class).

Print Assumptions formation_weakening.
Print Assumptions formation_scope.
Print Assumptions instance_head_closed.
Print Assumptions datatype_application_arity.
Print Assumptions bare_datatype_arity.
Print Assumptions requirement_arity.
Print Assumptions omitted_requires_agree.
