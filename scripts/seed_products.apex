List<Product2> products = new List<Product2>{

    // ── Structural Steel ──────────────────────────────────────────────
    new Product2(Name='TMT Fe500 8mm',            ProductCode='STL-001', Family='Structural Steel',  IsActive=true, Description='TMT reinforcement bar Fe500 grade, 8mm dia'),
    new Product2(Name='TMT Fe500 10mm',           ProductCode='STL-002', Family='Structural Steel',  IsActive=true, Description='TMT reinforcement bar Fe500 grade, 10mm dia'),
    new Product2(Name='TMT Fe500 12mm',           ProductCode='STL-003', Family='Structural Steel',  IsActive=true, Description='TMT reinforcement bar Fe500 grade, 12mm dia'),
    new Product2(Name='TMT Fe500 16mm',           ProductCode='STL-004', Family='Structural Steel',  IsActive=true, Description='TMT reinforcement bar Fe500 grade, 16mm dia'),
    new Product2(Name='TMT Fe500 20mm',           ProductCode='STL-005', Family='Structural Steel',  IsActive=true, Description='TMT reinforcement bar Fe500 grade, 20mm dia'),
    new Product2(Name='TMT Fe500 25mm',           ProductCode='STL-006', Family='Structural Steel',  IsActive=true, Description='TMT reinforcement bar Fe500 grade, 25mm dia'),
    new Product2(Name='MS Angle 50x50x5',         ProductCode='STL-007', Family='Structural Steel',  IsActive=true, Description='Mild steel angle 50x50x5mm'),
    new Product2(Name='MS Channel 100x50',        ProductCode='STL-008', Family='Structural Steel',  IsActive=true, Description='Mild steel channel ISMC 100'),
    new Product2(Name='MS I-Beam ISMB 150',       ProductCode='STL-009', Family='Structural Steel',  IsActive=true, Description='Mild steel I-beam ISMB 150'),
    new Product2(Name='MS Flat Bar 50x6',         ProductCode='STL-010', Family='Structural Steel',  IsActive=true, Description='Mild steel flat bar 50x6mm'),
    new Product2(Name='Binding Wire 16 Gauge',    ProductCode='STL-011', Family='Structural Steel',  IsActive=true, Description='Annealed binding wire, 16 gauge'),

    // ── Cement & Concrete ─────────────────────────────────────────────
    new Product2(Name='Cement OPC 53 Grade',      ProductCode='CMT-001', Family='Cement & Concrete', IsActive=true, Description='Ordinary Portland Cement 53 grade, 50kg bag'),
    new Product2(Name='Cement PPC',               ProductCode='CMT-002', Family='Cement & Concrete', IsActive=true, Description='Portland Pozzolana Cement, 50kg bag'),
    new Product2(Name='RMC M20',                  ProductCode='CMT-003', Family='Cement & Concrete', IsActive=true, Description='Ready Mix Concrete M20 grade'),
    new Product2(Name='RMC M25',                  ProductCode='CMT-004', Family='Cement & Concrete', IsActive=true, Description='Ready Mix Concrete M25 grade'),
    new Product2(Name='RMC M30',                  ProductCode='CMT-005', Family='Cement & Concrete', IsActive=true, Description='Ready Mix Concrete M30 grade'),
    new Product2(Name='River Sand',               ProductCode='CMT-006', Family='Cement & Concrete', IsActive=true, Description='Washed river sand, zone II'),
    new Product2(Name='M-Sand (Manufactured)',    ProductCode='CMT-007', Family='Cement & Concrete', IsActive=true, Description='Manufactured sand as per IS 383'),
    new Product2(Name='Coarse Aggregate 20mm',    ProductCode='CMT-008', Family='Cement & Concrete', IsActive=true, Description='Crushed stone aggregate, 20mm graded'),
    new Product2(Name='Coarse Aggregate 10mm',    ProductCode='CMT-009', Family='Cement & Concrete', IsActive=true, Description='Crushed stone aggregate, 10mm graded'),

    // ── Masonry ───────────────────────────────────────────────────────
    new Product2(Name='Red Brick First Class',    ProductCode='MSN-001', Family='Masonry',           IsActive=true, Description='First class red clay bricks, 230x115x75mm'),
    new Product2(Name='AAC Block 200mm',          ProductCode='MSN-002', Family='Masonry',           IsActive=true, Description='Autoclaved aerated concrete block, 600x200x200mm'),
    new Product2(Name='AAC Block 100mm',          ProductCode='MSN-003', Family='Masonry',           IsActive=true, Description='Autoclaved aerated concrete block, 600x200x100mm'),
    new Product2(Name='Fly Ash Brick',            ProductCode='MSN-004', Family='Masonry',           IsActive=true, Description='Fly ash brick 230x115x75mm'),
    new Product2(Name='Block Jointing Mortar',    ProductCode='MSN-005', Family='Masonry',           IsActive=true, Description='Ready-mix dry mortar for AAC block jointing, 20kg bag'),

    // ── Formwork ──────────────────────────────────────────────────────
    new Product2(Name='Shuttering Plywood 12mm',  ProductCode='FRM-001', Family='Formwork',          IsActive=true, Description='Film-faced shuttering plywood, 2440x1220x12mm'),
    new Product2(Name='Shuttering Plywood 18mm',  ProductCode='FRM-002', Family='Formwork',          IsActive=true, Description='Film-faced shuttering plywood, 2440x1220x18mm'),
    new Product2(Name='Acro Jack / Prop',         ProductCode='FRM-003', Family='Formwork',          IsActive=true, Description='Telescopic steel prop, adjustable 2.0–3.5m'),
    new Product2(Name='Shuttering Oil',           ProductCode='FRM-004', Family='Formwork',          IsActive=true, Description='Mould release oil for formwork, 200L drum'),
    new Product2(Name='H-Frame Scaffolding',      ProductCode='FRM-005', Family='Formwork',          IsActive=true, Description='H-frame scaffolding system set'),

    // ── Plumbing ──────────────────────────────────────────────────────
    new Product2(Name='GI Pipe 25mm (Class B)',   ProductCode='PLB-001', Family='Plumbing',          IsActive=true, Description='Galvanised iron pipe 25mm NB, Class B, per metre'),
    new Product2(Name='GI Pipe 50mm (Class B)',   ProductCode='PLB-002', Family='Plumbing',          IsActive=true, Description='Galvanised iron pipe 50mm NB, Class B, per metre'),
    new Product2(Name='UPVC Pipe 110mm SWR',      ProductCode='PLB-003', Family='Plumbing',          IsActive=true, Description='UPVC soil & waste pipe 110mm, 3m length'),
    new Product2(Name='CPVC Pipe 25mm',           ProductCode='PLB-004', Family='Plumbing',          IsActive=true, Description='CPVC hot & cold water pipe 25mm, 3m length'),
    new Product2(Name='MS ERW Pipe 50mm',         ProductCode='PLB-005', Family='Plumbing',          IsActive=true, Description='MS ERW pipe 50mm NB, per metre'),

    // ── Electrical ────────────────────────────────────────────────────
    new Product2(Name='FR Cable 2.5mm² (4-core)', ProductCode='ELC-001', Family='Electrical',        IsActive=true, Description='FR PVC insulated copper cable 2.5mm², 4-core, per metre'),
    new Product2(Name='FR Cable 4mm² (4-core)',   ProductCode='ELC-002', Family='Electrical',        IsActive=true, Description='FR PVC insulated copper cable 4mm², 4-core, per metre'),
    new Product2(Name='FR Cable 6mm² (4-core)',   ProductCode='ELC-003', Family='Electrical',        IsActive=true, Description='FR PVC insulated copper cable 6mm², 4-core, per metre'),
    new Product2(Name='Conduit PVC 20mm',         ProductCode='ELC-004', Family='Electrical',        IsActive=true, Description='PVC rigid conduit 20mm dia, 3m length'),
    new Product2(Name='Conduit PVC 32mm',         ProductCode='ELC-005', Family='Electrical',        IsActive=true, Description='PVC rigid conduit 32mm dia, 3m length'),
    new Product2(Name='DB Box 8-way SPN',         ProductCode='ELC-006', Family='Electrical',        IsActive=true, Description='Distribution box, 8-way single-phase neutral'),
    new Product2(Name='MCB 32A Single Pole',      ProductCode='ELC-007', Family='Electrical',        IsActive=true, Description='Miniature circuit breaker 32A, 1P, 10kA'),

    // ── Finishing ─────────────────────────────────────────────────────
    new Product2(Name='Gypsum Plaster 20mm',      ProductCode='FIN-001', Family='Finishing',         IsActive=true, Description='Machine-applied gypsum plaster, 25kg bag'),
    new Product2(Name='Sand Face Plaster',        ProductCode='FIN-002', Family='Finishing',         IsActive=true, Description='Exterior sand face plaster, 40kg bag'),
    new Product2(Name='Wall Putty Interior',      ProductCode='FIN-003', Family='Finishing',         IsActive=true, Description='Acrylic wall putty for interior, 20kg bag'),
    new Product2(Name='Waterproofing Compound',   ProductCode='FIN-004', Family='Finishing',         IsActive=true, Description='Crystalline waterproofing compound, 25kg bag'),
    new Product2(Name='Tile Adhesive',            ProductCode='FIN-005', Family='Finishing',         IsActive=true, Description='Polymer-modified tile adhesive C1, 20kg bag'),
    new Product2(Name='Ceramic Floor Tile 600x600', ProductCode='FIN-006', Family='Finishing',       IsActive=true, Description='Ceramic floor tile 600x600mm, box of 4 tiles'),
    new Product2(Name='Vitrified Tile 800x800',   ProductCode='FIN-007', Family='Finishing',         IsActive=true, Description='Double-charge vitrified tile 800x800mm, box'),
    new Product2(Name='Paint Exterior Emulsion',  ProductCode='FIN-008', Family='Finishing',         IsActive=true, Description='Weatherproof exterior emulsion paint, 20L'),
    new Product2(Name='Paint Interior Emulsion',  ProductCode='FIN-009', Family='Finishing',         IsActive=true, Description='Premium interior emulsion paint, 20L'),

    // ── Hardware & Fasteners ─────────────────────────────────────────
    new Product2(Name='Anchor Bolt M12x150',      ProductCode='HRD-001', Family='Hardware',          IsActive=true, Description='Chemical / expansion anchor bolt M12x150mm'),
    new Product2(Name='Hex Bolt M16x60 (GrB)',    ProductCode='HRD-002', Family='Hardware',          IsActive=true, Description='Hot-dip galvanised hex bolt M16x60mm with nut & washer'),
    new Product2(Name='Nails Round Wire 3"',      ProductCode='HRD-003', Family='Hardware',          IsActive=true, Description='Round wire nails 3 inch, 5kg box'),
    new Product2(Name='GI Wire Mesh 150x150',     ProductCode='HRD-004', Family='Hardware',          IsActive=true, Description='Galvanised welded wire mesh 150x150x4mm, per m²'),
    new Product2(Name='Expansion Joint Filler',   ProductCode='HRD-005', Family='Hardware',          IsActive=true, Description='Bituminous fibre expansion joint filler board, 12mm x 1.2m x 2.4m')
};

insert products;
System.debug('Created ' + products.size() + ' products.');
