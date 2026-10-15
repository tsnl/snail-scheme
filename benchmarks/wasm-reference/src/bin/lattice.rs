use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Lattice elements and their partial order ----

enum Element {
    Level(bool),
    Sequence(Vec<Rc<Element>>),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Order {
    Less,
    More,
    Equal,
    Uncomparable,
}

fn compare(left: &Element, right: &Element) -> Order {
    match (left, right) {
        (Element::Level(left), Element::Level(right)) => match left.cmp(right) {
            std::cmp::Ordering::Less => Order::Less,
            std::cmp::Ordering::Greater => Order::More,
            std::cmp::Ordering::Equal => Order::Equal,
        },
        (Element::Sequence(left), Element::Sequence(right)) => compare_sequences(left, right),
        _ => panic!("elements belong to different lattices"),
    }
}

fn compare_sequences(left: &[Rc<Element>], right: &[Rc<Element>]) -> Order {
    let mut fixed = Order::Equal;
    for (left, right) in left.iter().zip(right) {
        let probe = compare(left, right);
        if probe == Order::Uncomparable
            || (probe != Order::Equal && fixed != Order::Equal && probe != fixed)
        {
            return Order::Uncomparable;
        }
        if probe != Order::Equal {
            fixed = probe;
        }
    }
    fixed
}

// ---- Monotone-map search ----

// Each branch extends a persistent assignment list, as the Scheme search does.
// Result sequences retain Rc references to existing target lattice elements.
struct Mapping {
    source: Rc<Element>,
    target: Rc<Element>,
    rest: Option<Rc<Mapping>>,
}

fn preceding_images(
    partial: &Option<Rc<Mapping>>,
    next: &Element,
    relation: Order,
) -> Vec<Rc<Element>> {
    let mut images = Vec::new();
    let mut rest = partial.as_deref();
    while let Some(mapping) = rest {
        if compare(&mapping.source, next) == relation {
            images.push(mapping.target.clone());
        }
        rest = mapping.rest.as_deref();
    }
    images
}

fn allowed_targets(
    target: &[Rc<Element>],
    partial: &Option<Rc<Mapping>>,
    next: &Element,
) -> Vec<Rc<Element>> {
    let less = preceding_images(partial, next, Order::Less);
    let more = preceding_images(partial, next, Order::More);
    target
        .iter()
        .filter(|candidate| {
            less.iter()
                .all(|image| matches!(compare(image, candidate), Order::Less | Order::Equal))
                && more
                    .iter()
                    .all(|image| matches!(compare(image, candidate), Order::More | Order::Equal))
        })
        .cloned()
        .collect()
}

fn mapping_sequence(partial: &Option<Rc<Mapping>>) -> Rc<Element> {
    let mut values = Vec::new();
    let mut rest = partial.as_deref();
    while let Some(mapping) = rest {
        values.push(mapping.target.clone());
        rest = mapping.rest.as_deref();
    }
    Rc::new(Element::Sequence(values))
}

fn enumerate_maps(
    source: &[Rc<Element>],
    target: &[Rc<Element>],
    partial: &Option<Rc<Mapping>>,
) -> Vec<Rc<Element>> {
    let Some((next, rest)) = source.split_first() else {
        return vec![mapping_sequence(partial)];
    };
    let mut maps = Vec::new();
    for image in allowed_targets(target, partial, next) {
        let extended = Some(Rc::new(Mapping {
            source: next.clone(),
            target: image,
            rest: partial.clone(),
        }));
        maps.extend(enumerate_maps(rest, target, &extended));
    }
    maps
}

fn count_maps(
    source: &[Rc<Element>],
    target: &[Rc<Element>],
    partial: &Option<Rc<Mapping>>,
) -> u64 {
    let Some((next, rest)) = source.split_first() else {
        return 1;
    };
    let mut counts = Vec::new();
    for image in allowed_targets(target, partial, next) {
        let extended = Some(Rc::new(Mapping {
            source: next.clone(),
            target: image,
            rest: partial.clone(),
        }));
        counts.push(count_maps(rest, target, &extended));
    }
    counts.iter().sum()
}

fn run(problem: usize) -> u64 {
    let l2 = vec![
        Rc::new(Element::Level(false)),
        Rc::new(Element::Level(true)),
    ];
    let l3 = enumerate_maps(&l2, &l2, &None);
    let l4 = enumerate_maps(&l3, &l3, &None);
    black_box(count_maps(&l2, &l2, &None));
    black_box(count_maps(&l3, &l3, &None));
    black_box(count_maps(&l2, &l3, &None));
    black_box(count_maps(&l3, &l2, &None));
    match problem {
        33 => count_maps(&l3, &l3, &None),
        44 => count_maps(&l4, &l4, &None),
        45 => count_maps(&l4, &enumerate_maps(&l4, &l4, &None), &None),
        54 => count_maps(&enumerate_maps(&l4, &l4, &None), &l4, &None),
        55 => {
            let l5 = enumerate_maps(&l4, &l4, &None);
            count_maps(&l5, &l5, &None)
        }
        _ => panic!("unanticipated lattice problem"),
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let count = values[0].number();
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run(black_box(values[1].number())));
    }
    assert_eq!(result, values[2].number() as u64);
    report("lattice", count, start, result);
    Ok(())
}
