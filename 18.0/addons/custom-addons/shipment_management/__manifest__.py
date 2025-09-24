
{
    "name": "shipment management",
    "summary": "automatic logistics price calculation process: import export",
    "description": "automatic logistics price calculation process: import export",
    "version": "1.0",
    "licence": 'LGPL-3',
    "category": "sales",
    "author": "Tayssir Werfelli",
    "website": "",
    "depends": ["sale"],
    "data": [
        "security/ir.model.access.csv",

        "data/pricing_scale_initial_data.xml",
        "data/shipment_sequence.xml",

        "views/pricing_scale_views.xml",
        "views/shipment_views.xml",
        "views/res_partner_views.xml",
        "views/shipment_vehicle_category_views.xml",
        "views/shipment_vehicle_views.xml",
        "views/sale_order_views.xml",



        "views/shipment_menus.xml",
    ],
    'post_init_hook': 'initialize_pricing_scale',
}
