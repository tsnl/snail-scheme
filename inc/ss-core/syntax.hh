// // References:
// // - https://www.gnu.org/software/guile/manual/html_node/Syntax-Case.html

// #pragma once

// #include "ss-core/intern.hh"
// #include "ss-core/object.hh"

// ///
// // Syntax-case
// // see p.23 of R7RS-Small
// //

// namespace ss {

//     class Expander;
//     class ExpanderEnv;

//     // SubPattern
//     class SubPattern {
//     protected:
//         SubPattern() = default;
//     public:
//         enum class NodeKind {
//             Identifier, Constant,
//             PatternList,
//             PatternVector
//         };
//     public:
//         static SubPattern* parse(Expander* e, ExpanderEnv* env, OBJECT pattern);
//     };

//     // SubTemplate
//     class SubTemplate {
//     protected:
//         SubTemplate() = default;
//     public:
//         enum class NodeKind {
//             Identifier, Constant,
//             List,
//             ElementVector
//         };
//     public:
//         static SubTemplate* parse(Expander* e, ExpanderEnv* env, OBJECT pattern);
//     };

//     // TODO: implement SyntaxCase

// }   // namespace ss
