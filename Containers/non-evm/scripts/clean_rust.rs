use std::env;
use std::fs;
use syn::{visit_mut::VisitMut, File, Item, ItemFn, FnArg, Pat};

struct Cleaner;

impl VisitMut for Cleaner {
    fn visit_item_fn_mut(&mut self, i: &mut ItemFn) {
        // Prefix unused arguments with _
        for input in i.sig.inputs.iter_mut() {
            if let FnArg::Typed(pat_type) = input {
                if let Pat::Ident(ident) = &mut *pat_type.pat {
                    let name = ident.ident.to_string();
                    if !i.block.stmts.iter().any(|stmt| stmt.to_token_stream().to_string().contains(&name)) {
                        ident.ident = syn::Ident::new(&format!("_{}", name), ident.ident.span());
                    }
                }
            }
        }
        syn::visit_mut::visit_item_fn_mut(self, i);
    }
    fn visit_item_mut(&mut self, item: &mut Item) {
        // Remove unused imports (simple heuristic: any use not used in code)
        if let Item::Use(u) = item {
            let path = u.tree.to_token_stream().to_string();
            // crude: remove if not used elsewhere
            // For best results, use a linter (like rust-analyzer) or enhance this logic
            if !path.contains("solana_program") && !path.contains("solana_sdk") {
                *item = Item::Verbatim(proc_macro2::TokenStream::new());
            }
        }
        syn::visit_mut::visit_item_mut(self, item);
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: clean_rust <input_file>");
        std::process::exit(1);
    }
    let input_path = &args[1];
    let src = fs::read_to_string(input_path).expect("Failed to read file");
    let mut syntax: File = syn::parse_file(&src).expect("Failed to parse Rust file");
    Cleaner.visit_file_mut(&mut syntax);
    let cleaned = prettyplease::unparse(&syntax);
    fs::write(input_path, cleaned).expect("Failed to write cleaned file");
}
