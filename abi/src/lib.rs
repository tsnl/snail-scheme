//! Export ordinary scalar Rust functions through a deliberately small C ABI.
//! The attribute takes one stable symbol string. Parameters/results support
//! i32 and u32; a missing result or () means void. Unsafe functions stay unsafe.
//! It generates no conversions, checks, allocation, or export registry.

use proc_macro::TokenStream;
use quote::{format_ident, quote};
use syn::{FnArg, ItemFn, LitStr, Pat, ReturnType, Type, ext::IdentExt, parse_macro_input};

// ---- Export wrapper ----

#[proc_macro_attribute]
pub fn export(attribute: TokenStream, item: TokenStream) -> TokenStream {
    let symbol = parse_macro_input!(attribute as LitStr);
    let function = parse_macro_input!(item as ItemFn);
    match expand(&symbol, &function) {
        Ok(output) => output.into(),
        Err(error) => error.into_compile_error().into(),
    }
}

fn scalar(ty: &Type) -> bool {
    matches!(ty, Type::Path(path) if path.qself.is_none()
        && (path.path.is_ident("i32") || path.path.is_ident("u32")))
}

fn arguments(function: &ItemFn) -> syn::Result<Vec<&syn::Ident>> {
    function
        .sig
        .inputs
        .iter()
        .map(|argument| match argument {
            FnArg::Typed(argument) if scalar(&argument.ty) => match argument.pat.as_ref() {
                Pat::Ident(name) if name.by_ref.is_none() && name.subpat.is_none() => {
                    Ok(&name.ident)
                }
                _ => Err(syn::Error::new_spanned(
                    argument,
                    "export requires named scalar arguments",
                )),
            },
            _ => Err(syn::Error::new_spanned(
                argument,
                "export arguments must be i32 or u32",
            )),
        })
        .collect()
}

fn validate(function: &ItemFn) -> syn::Result<()> {
    let signature = &function.sig;
    if signature.asyncness.is_some()
        || signature.abi.is_some()
        || signature.variadic.is_some()
        || !signature.generics.params.is_empty()
        || signature.generics.where_clause.is_some()
    {
        return Err(syn::Error::new_spanned(
            signature,
            "export requires a nongeneric Rust function",
        ));
    }
    match &signature.output {
        ReturnType::Default => Ok(()),
        ReturnType::Type(_, ty)
            if scalar(ty) || matches!(ty.as_ref(), Type::Tuple(t) if t.elems.is_empty()) =>
        {
            Ok(())
        }
        output => Err(syn::Error::new_spanned(
            output,
            "export result must be i32, u32, or ()",
        )),
    }
}

fn expand(symbol: &LitStr, function: &ItemFn) -> syn::Result<proc_macro2::TokenStream> {
    validate(function)?;
    if symbol.value().is_empty() || symbol.value().contains('\0') {
        return Err(syn::Error::new_spanned(
            symbol,
            "export symbol must be nonempty and contain no NUL",
        ));
    }
    let names = arguments(function)?;
    let name = &function.sig.ident;
    let wrapper = format_ident!("__snail_export_{}", name.unraw());
    let (inputs, output, unsafety) = (
        &function.sig.inputs,
        &function.sig.output,
        &function.sig.unsafety,
    );
    let inline = function
        .attrs
        .iter()
        .filter(|attribute| attribute.path().is_ident("inline"));
    let invoke = if unsafety.is_some() {
        quote!(unsafe { #name(#(#names),*) })
    } else {
        quote!(#name(#(#names),*))
    };
    Ok(quote! {
        #function
        // rustc 1.95 retains alwaysinline on exported definitions despite its
        // warning. Optimized artifact tests verify the effect of this hint.
        #[allow(unused_attributes)]
        #[unsafe(export_name = #symbol)]
        #(#inline)*
        pub #unsafety extern "C" fn #wrapper(#inputs) #output { #invoke }
    })
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use syn::parse_quote;

    fn check(source: &str) -> syn::Result<proc_macro2::TokenStream> {
        expand(&parse_quote!("example_export"), &syn::parse_str(source)?)
    }

    #[test]
    fn exports_scalar_and_unit_functions() {
        for source in [
            "fn sum(a: i32, b: u32) -> i32 { a }",
            "fn unit() {}",
            "unsafe fn unchecked(value: u32) -> u32 { value }",
            "fn unit() -> () {}",
            "fn r#type(value: u32) -> u32 { value }",
        ] {
            let output = check(source).unwrap().to_string();
            assert!(output.contains("extern \"C\""));
            assert!(output.contains("example_export"));
        }
    }

    #[test]
    fn rejects_unsupported_signatures() {
        for source in [
            "fn f(x: bool) {}",
            "fn f(x: &u32) {}",
            "fn f(x: (u32, u32)) {}",
            "fn f<T>(x: T) {}",
            "async fn f() {}",
            "fn f() -> bool { false }",
            "fn f((x, y): (u32, u32)) {}",
            "extern \"C\" fn f() {}",
        ] {
            assert!(check(source).is_err(), "accepted {source}");
        }
    }
}
