;; (snail core base) for the Chibi host: the part of the Snail-Core prelude that the
;; compiler uses, implemented with Chibi's own procedures. Lists are Chibi
;; pairs, so `Cons` and `Nil` construct and match pairs; Option and Pair are
;; structs as in Snail-Core.
(define-library (snail core base)
  (export
   define lambda if begin let let* letrec cond case when unless and or do
   define-syntax syntax-rules quote else => _ ...
   : type ann type-convert struct enum match effect handle
   + - * quotient remainder modulo = < <= > >= negate abs min max not
   unit panic drop
   i64-and i64-or i64-xor i64-shift-left i64-shift-right/logical
   i64->string string->i64 u8->i32 i32->u8 i32->i64 i64->i32 digit-value
   Option Some None Result Ok Err Never absurd Pair
   Cons Nil list null? length reverse append map map-indexed for-each filter fold-left fold-right
   list-ref
   list-tail
   any?
   every?
   find
   member?
   iota
   concatenate
   delete-duplicates
   take
   list-drop
   list-sort
   last
   list-index
   assoc-ref
   zip
   char->integer integer->char char=? char<? char-whitespace? char-numeric? char-alphabetic?
   string string-length string-ref string-append substring string=? string<? make-string
   string->list list->string string-join string-concatenate string-generate string-index
   string->vector vector->string
   vector-length
   vector-ref
   make-vector
   vector-generate
   vector-set
   vector-append
   vector-concatenate
   subvector
   vector-map vector-for-each vector-fold vector->list list->vector
   make-array array-length array-ref array-set! array->vector vector->array
   ref ref-get ref-set!
   ;; ---- Field path exports (generated) ----
   ::a
   ::access
   ::aliases
   ::annotations
   ::arguments
   ::arity
   ::around-main
   ::around-main?
   ::artifact-uses
   ::artifacts
   ::b
   ::base
   ::bindings
   ::body
   ::body-key
   ::borrowed
   ::bound
   ::browser?
   ::builds
   ::bytes
   ::call
   ::case
   ::case-id-equal
   ::cases
   ::chars
   ::checker
   ::class
   ::classes
   ::clauses
   ::column
   ::compiled
   ::compiled?
   ::components
   ::confined
   ::confining
   ::constraints
   ::constructor
   ::constructors
   ::control
   ::control?
   ::converting
   ::copied
   ::copy
   ::count
   ::counter
   ::data
   ::declarations
   ::declared
   ::decode
   ::decode-case-id
   ::defaults
   ::definition
   ::definitions
   ::delta
   ::denotation
   ::derives
   ::deriving
   ::deserialize
   ::digest
   ::digests
   ::directories
   ::directory
   ::discharged
   ::dispatched
   ::drop?
   ::earlier
   ::edges
   ::effect
   ::effects
   ::emission
   ::emitted
   ::empty
   ::encode
   ::encode-case-id
   ::end
   ::entry
   ::enum?
   ::env
   ::equations
   ::erased
   ::evidence
   ::exclusive
   ::exit
   ::expand
   ::expanded
   ::expansion
   ::exported
   ::exports
   ::external?
   ::f
   ::failed
   ::family
   ::feedback
   ::field
   ::fields
   ::file
   ::files
   ::finished
   ::first
   ::first-unused-number
   ::fixed
   ::flags
   ::form
   ::forms
   ::found
   ::found?
   ::frames
   ::from
   ::function?
   ::functions
   ::gathering?
   ::generate
   ::generated
   ::givens
   ::global
   ::globals
   ::handle
   ::handles
   ::head
   ::helpers
   ::holder
   ::home
   ::id
   ::identifier
   ::implementation
   ::implementations
   ::imported
   ::imports
   ::index
   ::initializers
   ::inline?
   ::input
   ::inputs
   ::instance
   ::instance-sets
   ::instances
   ::interface
   ::interfaces
   ::items
   ::key
   ::keys
   ::keyword
   ::kind
   ::known
   ::label
   ::labels
   ::last
   ::latent
   ::left
   ::lets
   ::libraries
   ::library
   ::line
   ::line-starts
   ::lines
   ::link
   ::links
   ::listing
   ::literals
   ::live
   ::loading
   ::loc
   ::local
   ::locals
   ::low
   ::macro
   ::main
   ::mark
   ::marks
   ::matches
   ::meaning
   ::member
   ::members
   ::memo
   ::message
   ::metadata
   ::method
   ::methods
   ::missing
   ::module
   ::more
   ::move?
   ::mutable?
   ::name
   ::name-loc
   ::names
   ::naming
   ::needs
   ::next
   ::nodes
   ::number
   ::numbering
   ::offer
   ::offers
   ::offset
   ::open
   ::operands
   ::operation
   ::operations
   ::order
   ::original
   ::outline
   ::outlined
   ::output
   ::outputs
   ::own
   ::owned?
   ::owner
   ::pairs
   ::panic
   ::parameters
   ::params
   ::path
   ::pattern
   ::patterns
   ::pending
   ::pending-count
   ::performed
   ::phase
   ::placed
   ::position
   ::predecessor
   ::prefix
   ::prepend
   ::printed
   ::problems
   ::program
   ::public
   ::reached
   ::read
   ::reading
   ::recipe
   ::relative
   ::renamed
   ::reps
   ::requirements
   ::requires
   ::resolving
   ::result
   ::resumes
   ::returns
   ::right
   ::roots
   ::row
   ::row-index
   ::rows
   ::rules
   ::runs
   ::scanned
   ::scheme
   ::schemes
   ::scope
   ::scope-count
   ::scopes
   ::scratch
   ::second
   ::selected
   ::selecting
   ::selector
   ::self
   ::serial
   ::serialize
   ::set
   ::sets
   ::setup
   ::shape
   ::show
   ::signed
   ::site
   ::solution
   ::source
   ::specs
   ::stack
   ::stamp
   ::starts
   ::state
   ::statements
   ::steps
   ::symbol
   ::tag
   ::tail
   ::target
   ::targets
   ::template
   ::term
   ::text
   ::top
   ::top-count
   ::tops
   ::type
   ::type-ids
   ::typed
   ::types
   ::unit
   ::use
   ::value
   ::values
   ::variable
   ::variables
   ::vars
   ::visited
   ::waiting
   ::written
   ::x
   ::y
   ;; ---- End field path exports ----
   )
  (import
   (rename (scheme base) (case scheme-case))
   (only (chibi) _ ...)
   (except (scheme char) char-whitespace? char-numeric? char-alphabetic?)
   (rename (srfi 1) (drop list-drop))
   (rename (only (srfi 132) list-stable-sort) (list-stable-sort list-sort))
   (srfi 151)
   (snail stage0 forms))
  (begin

    ;; ---- Field paths ----

    ;; One dispatcher per `::label` the compiler's sources read, over stage
    ;; 0's `field-of`, since Chibi has no class per label. Generated by
    ;; scripts/chibi-paths, which `make test-chibi` and `make bootstrap`
    ;; check is current.
    ;; ---- Field paths (generated) ----
    (define (::a value) (field-of value (quote a)))
    (define (::access value) (field-of value (quote access)))
    (define (::aliases value) (field-of value (quote aliases)))
    (define (::annotations value) (field-of value (quote annotations)))
    (define (::arguments value) (field-of value (quote arguments)))
    (define (::arity value) (field-of value (quote arity)))
    (define (::around-main value) (field-of value (quote around-main)))
    (define (::around-main? value) (field-of value (quote around-main?)))
    (define (::artifact-uses value) (field-of value (quote artifact-uses)))
    (define (::artifacts value) (field-of value (quote artifacts)))
    (define (::b value) (field-of value (quote b)))
    (define (::base value) (field-of value (quote base)))
    (define (::bindings value) (field-of value (quote bindings)))
    (define (::body value) (field-of value (quote body)))
    (define (::body-key value) (field-of value (quote body-key)))
    (define (::borrowed value) (field-of value (quote borrowed)))
    (define (::bound value) (field-of value (quote bound)))
    (define (::browser? value) (field-of value (quote browser?)))
    (define (::builds value) (field-of value (quote builds)))
    (define (::bytes value) (field-of value (quote bytes)))
    (define (::call value) (field-of value (quote call)))
    (define (::case value) (field-of value (quote case)))
    (define (::case-id-equal value) (field-of value (quote case-id-equal)))
    (define (::cases value) (field-of value (quote cases)))
    (define (::chars value) (field-of value (quote chars)))
    (define (::checker value) (field-of value (quote checker)))
    (define (::class value) (field-of value (quote class)))
    (define (::classes value) (field-of value (quote classes)))
    (define (::clauses value) (field-of value (quote clauses)))
    (define (::column value) (field-of value (quote column)))
    (define (::compiled value) (field-of value (quote compiled)))
    (define (::compiled? value) (field-of value (quote compiled?)))
    (define (::components value) (field-of value (quote components)))
    (define (::confined value) (field-of value (quote confined)))
    (define (::confining value) (field-of value (quote confining)))
    (define (::constraints value) (field-of value (quote constraints)))
    (define (::constructor value) (field-of value (quote constructor)))
    (define (::constructors value) (field-of value (quote constructors)))
    (define (::control value) (field-of value (quote control)))
    (define (::control? value) (field-of value (quote control?)))
    (define (::converting value) (field-of value (quote converting)))
    (define (::copied value) (field-of value (quote copied)))
    (define (::copy value) (field-of value (quote copy)))
    (define (::count value) (field-of value (quote count)))
    (define (::counter value) (field-of value (quote counter)))
    (define (::data value) (field-of value (quote data)))
    (define (::declarations value) (field-of value (quote declarations)))
    (define (::declared value) (field-of value (quote declared)))
    (define (::decode value) (field-of value (quote decode)))
    (define (::decode-case-id value) (field-of value (quote decode-case-id)))
    (define (::defaults value) (field-of value (quote defaults)))
    (define (::definition value) (field-of value (quote definition)))
    (define (::definitions value) (field-of value (quote definitions)))
    (define (::delta value) (field-of value (quote delta)))
    (define (::denotation value) (field-of value (quote denotation)))
    (define (::derives value) (field-of value (quote derives)))
    (define (::deriving value) (field-of value (quote deriving)))
    (define (::deserialize value) (field-of value (quote deserialize)))
    (define (::digest value) (field-of value (quote digest)))
    (define (::digests value) (field-of value (quote digests)))
    (define (::directories value) (field-of value (quote directories)))
    (define (::directory value) (field-of value (quote directory)))
    (define (::discharged value) (field-of value (quote discharged)))
    (define (::dispatched value) (field-of value (quote dispatched)))
    (define (::drop? value) (field-of value (quote drop?)))
    (define (::earlier value) (field-of value (quote earlier)))
    (define (::edges value) (field-of value (quote edges)))
    (define (::effect value) (field-of value (quote effect)))
    (define (::effects value) (field-of value (quote effects)))
    (define (::emission value) (field-of value (quote emission)))
    (define (::emitted value) (field-of value (quote emitted)))
    (define (::empty value) (field-of value (quote empty)))
    (define (::encode value) (field-of value (quote encode)))
    (define (::encode-case-id value) (field-of value (quote encode-case-id)))
    (define (::end value) (field-of value (quote end)))
    (define (::entry value) (field-of value (quote entry)))
    (define (::enum? value) (field-of value (quote enum?)))
    (define (::env value) (field-of value (quote env)))
    (define (::equations value) (field-of value (quote equations)))
    (define (::erased value) (field-of value (quote erased)))
    (define (::evidence value) (field-of value (quote evidence)))
    (define (::exclusive value) (field-of value (quote exclusive)))
    (define (::exit value) (field-of value (quote exit)))
    (define (::expand value) (field-of value (quote expand)))
    (define (::expanded value) (field-of value (quote expanded)))
    (define (::expansion value) (field-of value (quote expansion)))
    (define (::exported value) (field-of value (quote exported)))
    (define (::exports value) (field-of value (quote exports)))
    (define (::external? value) (field-of value (quote external?)))
    (define (::f value) (field-of value (quote f)))
    (define (::failed value) (field-of value (quote failed)))
    (define (::family value) (field-of value (quote family)))
    (define (::feedback value) (field-of value (quote feedback)))
    (define (::field value) (field-of value (quote field)))
    (define (::fields value) (field-of value (quote fields)))
    (define (::file value) (field-of value (quote file)))
    (define (::files value) (field-of value (quote files)))
    (define (::finished value) (field-of value (quote finished)))
    (define (::first value) (field-of value (quote first)))
    (define (::first-unused-number value) (field-of value (quote first-unused-number)))
    (define (::fixed value) (field-of value (quote fixed)))
    (define (::flags value) (field-of value (quote flags)))
    (define (::form value) (field-of value (quote form)))
    (define (::forms value) (field-of value (quote forms)))
    (define (::found value) (field-of value (quote found)))
    (define (::found? value) (field-of value (quote found?)))
    (define (::frames value) (field-of value (quote frames)))
    (define (::from value) (field-of value (quote from)))
    (define (::function? value) (field-of value (quote function?)))
    (define (::functions value) (field-of value (quote functions)))
    (define (::gathering? value) (field-of value (quote gathering?)))
    (define (::generate value) (field-of value (quote generate)))
    (define (::generated value) (field-of value (quote generated)))
    (define (::givens value) (field-of value (quote givens)))
    (define (::global value) (field-of value (quote global)))
    (define (::globals value) (field-of value (quote globals)))
    (define (::handle value) (field-of value (quote handle)))
    (define (::handles value) (field-of value (quote handles)))
    (define (::head value) (field-of value (quote head)))
    (define (::helpers value) (field-of value (quote helpers)))
    (define (::holder value) (field-of value (quote holder)))
    (define (::home value) (field-of value (quote home)))
    (define (::id value) (field-of value (quote id)))
    (define (::identifier value) (field-of value (quote identifier)))
    (define (::implementation value) (field-of value (quote implementation)))
    (define (::implementations value) (field-of value (quote implementations)))
    (define (::imported value) (field-of value (quote imported)))
    (define (::imports value) (field-of value (quote imports)))
    (define (::index value) (field-of value (quote index)))
    (define (::initializers value) (field-of value (quote initializers)))
    (define (::inline? value) (field-of value (quote inline?)))
    (define (::input value) (field-of value (quote input)))
    (define (::inputs value) (field-of value (quote inputs)))
    (define (::instance value) (field-of value (quote instance)))
    (define (::instance-sets value) (field-of value (quote instance-sets)))
    (define (::instances value) (field-of value (quote instances)))
    (define (::interface value) (field-of value (quote interface)))
    (define (::interfaces value) (field-of value (quote interfaces)))
    (define (::items value) (field-of value (quote items)))
    (define (::key value) (field-of value (quote key)))
    (define (::keys value) (field-of value (quote keys)))
    (define (::keyword value) (field-of value (quote keyword)))
    (define (::kind value) (field-of value (quote kind)))
    (define (::known value) (field-of value (quote known)))
    (define (::label value) (field-of value (quote label)))
    (define (::labels value) (field-of value (quote labels)))
    (define (::last value) (field-of value (quote last)))
    (define (::latent value) (field-of value (quote latent)))
    (define (::left value) (field-of value (quote left)))
    (define (::lets value) (field-of value (quote lets)))
    (define (::libraries value) (field-of value (quote libraries)))
    (define (::library value) (field-of value (quote library)))
    (define (::line value) (field-of value (quote line)))
    (define (::line-starts value) (field-of value (quote line-starts)))
    (define (::lines value) (field-of value (quote lines)))
    (define (::link value) (field-of value (quote link)))
    (define (::links value) (field-of value (quote links)))
    (define (::listing value) (field-of value (quote listing)))
    (define (::literals value) (field-of value (quote literals)))
    (define (::live value) (field-of value (quote live)))
    (define (::loading value) (field-of value (quote loading)))
    (define (::loc value) (field-of value (quote loc)))
    (define (::local value) (field-of value (quote local)))
    (define (::locals value) (field-of value (quote locals)))
    (define (::low value) (field-of value (quote low)))
    (define (::macro value) (field-of value (quote macro)))
    (define (::main value) (field-of value (quote main)))
    (define (::mark value) (field-of value (quote mark)))
    (define (::marks value) (field-of value (quote marks)))
    (define (::matches value) (field-of value (quote matches)))
    (define (::meaning value) (field-of value (quote meaning)))
    (define (::member value) (field-of value (quote member)))
    (define (::members value) (field-of value (quote members)))
    (define (::memo value) (field-of value (quote memo)))
    (define (::message value) (field-of value (quote message)))
    (define (::metadata value) (field-of value (quote metadata)))
    (define (::method value) (field-of value (quote method)))
    (define (::methods value) (field-of value (quote methods)))
    (define (::missing value) (field-of value (quote missing)))
    (define (::module value) (field-of value (quote module)))
    (define (::more value) (field-of value (quote more)))
    (define (::move? value) (field-of value (quote move?)))
    (define (::mutable? value) (field-of value (quote mutable?)))
    (define (::name value) (field-of value (quote name)))
    (define (::name-loc value) (field-of value (quote name-loc)))
    (define (::names value) (field-of value (quote names)))
    (define (::naming value) (field-of value (quote naming)))
    (define (::needs value) (field-of value (quote needs)))
    (define (::next value) (field-of value (quote next)))
    (define (::nodes value) (field-of value (quote nodes)))
    (define (::number value) (field-of value (quote number)))
    (define (::numbering value) (field-of value (quote numbering)))
    (define (::offer value) (field-of value (quote offer)))
    (define (::offers value) (field-of value (quote offers)))
    (define (::offset value) (field-of value (quote offset)))
    (define (::open value) (field-of value (quote open)))
    (define (::operands value) (field-of value (quote operands)))
    (define (::operation value) (field-of value (quote operation)))
    (define (::operations value) (field-of value (quote operations)))
    (define (::order value) (field-of value (quote order)))
    (define (::original value) (field-of value (quote original)))
    (define (::outline value) (field-of value (quote outline)))
    (define (::outlined value) (field-of value (quote outlined)))
    (define (::output value) (field-of value (quote output)))
    (define (::outputs value) (field-of value (quote outputs)))
    (define (::own value) (field-of value (quote own)))
    (define (::owned? value) (field-of value (quote owned?)))
    (define (::owner value) (field-of value (quote owner)))
    (define (::pairs value) (field-of value (quote pairs)))
    (define (::panic value) (field-of value (quote panic)))
    (define (::parameters value) (field-of value (quote parameters)))
    (define (::params value) (field-of value (quote params)))
    (define (::path value) (field-of value (quote path)))
    (define (::pattern value) (field-of value (quote pattern)))
    (define (::patterns value) (field-of value (quote patterns)))
    (define (::pending value) (field-of value (quote pending)))
    (define (::pending-count value) (field-of value (quote pending-count)))
    (define (::performed value) (field-of value (quote performed)))
    (define (::phase value) (field-of value (quote phase)))
    (define (::placed value) (field-of value (quote placed)))
    (define (::position value) (field-of value (quote position)))
    (define (::predecessor value) (field-of value (quote predecessor)))
    (define (::prefix value) (field-of value (quote prefix)))
    (define (::prepend value) (field-of value (quote prepend)))
    (define (::printed value) (field-of value (quote printed)))
    (define (::problems value) (field-of value (quote problems)))
    (define (::program value) (field-of value (quote program)))
    (define (::public value) (field-of value (quote public)))
    (define (::reached value) (field-of value (quote reached)))
    (define (::read value) (field-of value (quote read)))
    (define (::reading value) (field-of value (quote reading)))
    (define (::recipe value) (field-of value (quote recipe)))
    (define (::relative value) (field-of value (quote relative)))
    (define (::renamed value) (field-of value (quote renamed)))
    (define (::reps value) (field-of value (quote reps)))
    (define (::requirements value) (field-of value (quote requirements)))
    (define (::requires value) (field-of value (quote requires)))
    (define (::resolving value) (field-of value (quote resolving)))
    (define (::result value) (field-of value (quote result)))
    (define (::resumes value) (field-of value (quote resumes)))
    (define (::returns value) (field-of value (quote returns)))
    (define (::right value) (field-of value (quote right)))
    (define (::roots value) (field-of value (quote roots)))
    (define (::row value) (field-of value (quote row)))
    (define (::row-index value) (field-of value (quote row-index)))
    (define (::rows value) (field-of value (quote rows)))
    (define (::rules value) (field-of value (quote rules)))
    (define (::runs value) (field-of value (quote runs)))
    (define (::scanned value) (field-of value (quote scanned)))
    (define (::scheme value) (field-of value (quote scheme)))
    (define (::schemes value) (field-of value (quote schemes)))
    (define (::scope value) (field-of value (quote scope)))
    (define (::scope-count value) (field-of value (quote scope-count)))
    (define (::scopes value) (field-of value (quote scopes)))
    (define (::scratch value) (field-of value (quote scratch)))
    (define (::second value) (field-of value (quote second)))
    (define (::selected value) (field-of value (quote selected)))
    (define (::selecting value) (field-of value (quote selecting)))
    (define (::selector value) (field-of value (quote selector)))
    (define (::self value) (field-of value (quote self)))
    (define (::serial value) (field-of value (quote serial)))
    (define (::serialize value) (field-of value (quote serialize)))
    (define (::set value) (field-of value (quote set)))
    (define (::sets value) (field-of value (quote sets)))
    (define (::setup value) (field-of value (quote setup)))
    (define (::shape value) (field-of value (quote shape)))
    (define (::show value) (field-of value (quote show)))
    (define (::signed value) (field-of value (quote signed)))
    (define (::site value) (field-of value (quote site)))
    (define (::solution value) (field-of value (quote solution)))
    (define (::source value) (field-of value (quote source)))
    (define (::specs value) (field-of value (quote specs)))
    (define (::stack value) (field-of value (quote stack)))
    (define (::stamp value) (field-of value (quote stamp)))
    (define (::starts value) (field-of value (quote starts)))
    (define (::state value) (field-of value (quote state)))
    (define (::statements value) (field-of value (quote statements)))
    (define (::steps value) (field-of value (quote steps)))
    (define (::symbol value) (field-of value (quote symbol)))
    (define (::tag value) (field-of value (quote tag)))
    (define (::tail value) (field-of value (quote tail)))
    (define (::target value) (field-of value (quote target)))
    (define (::targets value) (field-of value (quote targets)))
    (define (::template value) (field-of value (quote template)))
    (define (::term value) (field-of value (quote term)))
    (define (::text value) (field-of value (quote text)))
    (define (::top value) (field-of value (quote top)))
    (define (::top-count value) (field-of value (quote top-count)))
    (define (::tops value) (field-of value (quote tops)))
    (define (::type value) (field-of value (quote type)))
    (define (::type-ids value) (field-of value (quote type-ids)))
    (define (::typed value) (field-of value (quote typed)))
    (define (::types value) (field-of value (quote types)))
    (define (::unit value) (field-of value (quote unit)))
    (define (::use value) (field-of value (quote use)))
    (define (::value value) (field-of value (quote value)))
    (define (::values value) (field-of value (quote values)))
    (define (::variable value) (field-of value (quote variable)))
    (define (::variables value) (field-of value (quote variables)))
    (define (::vars value) (field-of value (quote vars)))
    (define (::visited value) (field-of value (quote visited)))
    (define (::waiting value) (field-of value (quote waiting)))
    (define (::written value) (field-of value (quote written)))
    (define (::x value) (field-of value (quote x)))
    (define (::y value) (field-of value (quote y)))
    ;; ---- End field paths ----

    ;; ---- Forms ----

    ;; Snail-Core's `case` compares keys with `=`, which on strings is `string=?`.
    (define-syntax case
      (syntax-rules (else)
        ((_ key clause ...) (let ((value key)) (case-clauses value clause ...)))))

    (define-syntax case-clauses
      (syntax-rules (else)
        ((_ value (else body ...)) (begin body ...))
        ((_ value ((datum ...) body ...) clause ...)
         (if (member value (list datum ...)) (begin body ...) (case-clauses value clause ...)))))

    ;; ---- Values ----

    (define (unit) (if #f #f))

    (define (panic message) (error message))

    ;; Stage 0 has no FnOnce: the `resume` its handlers are handed cannot
    ;; resume (see (snail stage0 forms)), so dropping one releases nothing.
    (define (drop owned) (unit))

    (define (negate n) (- 0 n))

    (define (i64-and a b) (bitwise-and a b))
    (define (i64-or a b) (bitwise-ior a b))
    (define (i64-xor a b) (bitwise-xor a b))
    (define (i64-shift-left a n) (arithmetic-shift a n))
    (define (i64-shift-right/logical a n) (arithmetic-shift a (- 0 n)))

    (define (i64->string n) (number->string n))

    ;; Chibi's integers are unbounded, so conversions between widths only
    ;; wrap where Snail-Core's would: into a byte, or into 32 bits.
    (define (u8->i32 n) n)
    (define (i32->u8 n) (modulo n 256))
    (define (i32->i64 n) n)
    (define (i64->i32 n)
      (let ((low (modulo n 4294967296))) (if (>= low 2147483648) (- low 4294967296) low)))

    ;; None unless the whole text is an optionally signed decimal integer
    ;; that fits in 64 bits, as Snail-Core's says: Chibi's integers are
    ;; unbounded, so the range is checked here.
    (define (string->i64 text)
      (let ((n (and (> (string-length text) 0) (string->number text 10))))
        (if (and (exact-integer? n) (<= -9223372036854775808 n 9223372036854775807))
            (Some n)
            (None))))

    (enum (Result T E)
      (Ok ((value T)))
      (Err ((error E))))

    ;; No value has type Never, so `absurd` is never called: an operation
    ;; that answers Never escapes to its handler (snail stage0 forms).
    (enum Never)

    (define (absurd never)
      (error "absurd: no value has type Never" never))

    (enum (Option T)
      (Some ((value T)))
      (None))

    (struct (Pair A B)
      ((first A)
       (second B)))

    ;; ---- Lists ----

    (define (Cons head tail) (cons head tail))
    (define (Nil) '())

    ;; Snail-Core's `map` takes one list and calls `f` from left to right.
    (define (map f items)
      (let loop ((items items) (out '()))
        (if (null? items) (reverse out) (loop (cdr items) (cons (f (car items)) out)))))

    (define (zip as bs)
      (let loop ((as as) (bs bs) (out '()))
        (if (or (null? as) (null? bs))
            (reverse out)
            (loop (cdr as) (cdr bs) (cons (Pair (car as) (car bs)) out)))))

    (define (map-indexed f items)
      (let loop ((items items) (index 0) (out '()))
        (if (null? items)
            (reverse out)
            (loop (cdr items) (+ index 1) (cons (f index (car items)) out)))))

    (define (fold-left f initial items)
      (let loop ((items items) (result initial))
        (if (null? items) result (loop (cdr items) (f result (car items))))))

    (define (fold-right f initial items)
      (fold-left (lambda (result item) (f item result)) initial (reverse items)))

    (define (any? test items) (if (any test items) #t #f))
    (define (every? test items) (if (every test items) #t #f))

    (define (find test items)
      (let loop ((items items))
        (cond ((null? items) (None))
              ((test (car items)) (Some (car items)))
              (else (loop (cdr items))))))

    (define (member? value items) (if (member value items) #t #f))

    (define (concatenate lists) (fold-right append '() lists))

    (define (delete-duplicates same? items)
      (reverse (fold-left (lambda (kept item)
                            (if (any (lambda (other) (same? other item)) kept)
                                kept
                                (cons item kept)))
                          '() items)))

    (define (last items)
      (if (null? items) (None) (Some (car (reverse items)))))

    (define (assoc-ref entries key)
      (let loop ((entries entries))
        (cond ((null? entries) (None))
              ((equal? (::first (car entries)) key) (Some (::second (car entries))))
              (else (loop (cdr entries))))))

    (define (list-index test items)
      (let loop ((items items) (index 0))
        (cond ((null? items) (None))
              ((test (car items)) (Some index))
              (else (loop (cdr items) (+ index 1))))))

    ;; ---- Characters ----

    ;; Snail-Core's character classes are ASCII's, and these are its
    ;; definitions. Chibi's own follow Unicode, under which a no-break space
    ;; would end a token here and be part of one when compiled.
    (define (char-whitespace? char)
      (or (char=? char #\space) (char=? char #\tab) (char=? char #\newline) (char=? char #\return)))

    (define (char-numeric? char)
      (and (char<=? #\0 char) (char<=? char #\9)))

    (define (char-alphabetic? char)
      (or (and (char<=? #\a char) (char<=? char #\z)) (and (char<=? #\A char) (char<=? char #\Z))))

    ;; ---- Text ----

    (define (string-join texts separator)
      (if (null? texts)
          ""
          (fold-left (lambda (joined text) (string-append joined separator text))
                     (car texts)
                     (cdr texts))))

    ;; Without `apply`, which would push every string onto Chibi's stack.
    (define (string-concatenate texts)
      (let ((out (open-output-string)))
        (for-each (lambda (text) (write-string text out)) texts)
        (get-output-string out)))

    (define (string-generate count f)
      (let ((text (make-string count #\space)))
        (do ((index 0 (+ index 1))) ((= index count) text)
          (string-set! text index (f index)))))

    (define (string-index text char)
      (let loop ((index 0))
        (cond ((= index (string-length text)) (None))
              ((char=? (string-ref text index) char) (Some index))
              (else (loop (+ index 1))))))

    ;; ---- Vectors and arrays ----

    (define (vector-generate count f)
      (let ((items (make-vector count)))
        (do ((index 0 (+ index 1))) ((= index count) items)
          (vector-set! items index (f index)))))

    (define (vector-set items index value)
      (let ((copy (vector-copy items)))
        (vector-set! copy index value)
        copy))

    (define (subvector items start end) (vector-copy items start end))

    ;; Without `apply`, as `string-concatenate`.
    (define (vector-concatenate vectors)
      (let ((all (make-vector
                  (fold-left (lambda (total items) (+ total (vector-length items))) 0 vectors))))
        (fold-left
         (lambda (offset items) (vector-copy! all offset items) (+ offset (vector-length items)))
         0
         vectors)
        all))

    (define (vector-fold f initial items)
      (fold-left f initial (vector->list items)))

    (define (make-array count value) (make-vector count value))
    (define (array-length items) (vector-length items))
    (define (array-ref items index) (vector-ref items index))
    (define (array-set! items index value) (vector-set! items index value))
    (define (array->vector items) (vector-copy items))
    (define (vector->array items) (vector-copy items))

    ))
