
{
    "name": "Logistic pricing",
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
        "views/pricing_scale_views.xml",
        "views/sale_order_views.xml",
        "data/pricing_scale_initial_data.xml",
    ],
    'post_init_hook': 'initialize_pricing_scale',
}
