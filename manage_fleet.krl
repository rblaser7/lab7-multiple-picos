ruleset manage_fleet {
    meta {
        name "Manage Fleet"
        description <<
            Lab 7 Manage Fleet
        >>
        author "Ryan Blaser"
        logging on
        use module io.picolabs.subscription alias Subscriptions
        share vehicles, entVehicles
    }

    global {
        nameFromID = function(vehicle_id) {
            "Vehicle " + vehicle_id + " Pico"
        }
        vehicles = function() {
            Subscriptions:established("Tx_role","vehicle")
        }
        entVehicles = function() {
            ent:vehicles
        }
    }

    rule create_vehicle {
        select when car new_vehicle
        pre {
            vehicle_id = event:attr("vehicle_id")
            exists = ent:vehicles >< vehicle_id
        }
        if exists then
            send_directive("vehicle_ready", {"vehicle_id":vehicle_id})
        notfired {
            raise wrangler event "child_creation"
                attributes {    "name": nameFromID(vehicle_id),
                                "color": "#ffff00",
                                "vehicle_id" : vehicle_id,
                                "rids": "track_trips;trip_store;io.picolabs.subscription" }
        }
    }

    rule store_new_vehicle {
        select when wrangler child_initialized
        pre {
            my_eci = meta:eci
            vehicle_eci = event:attr("eci")
            the_vehicle = {"id": event:attr("id"), "eci": vehicle_eci}
            vehicle_id = event:attr("rs_attrs"){"vehicle_id"}
        }
        if vehicle_id.klog("found vehicle_id") then
            event:send({
                "eci": my_eci,
                "eid": "subscription",
                "domain": "wrangler",
                "type": "subscription",
                "attrs": { 
                    "name": nameFromID(vehicle_id),
                    "Rx_role": "fleet",
                    "Tx_role": "vehicle",
                    "channel_type": "subscription",
                    "wellKnown_Tx": vehicle_eci
                }
            })
        fired {
            ent:vehicles := ent:vehicles.defaultsTo({});
            ent:vehicles{[vehicle_id]} := the_vehicle;
        }
    }

    rule delete_vehicle {
        select when car unneeded_vehicle
        pre {
            vehicle_id = event:attr("vehicle_id")
            exists = ent:vehicles >< vehicle_id
            child_to_delete = nameFromID(vehicle_id)
        }
        if exists then
            send_directive("deleting_vehicle", {"vehicle_id":vehicle_id, "pico_id":vehicle_pico_id})
        fired {
            raise explicit event "delete_subscriptions";
            raise wrangler event "child_deletion"
                attributes {"name": child_to_delete};
            clear ent:vehicles{[vehicle_id]};
            raise explicit event "add_subscriptions"
        }
    }

    rule delete_subscriptions {
        select when explicit delete_subscriptions
        foreach Subscriptions:established("Tx_role","vehicle") setting(subscription)
            always {
                raise wrangler event "subscription_cancellation"
                    attributes {"Tx":subscription{"Tx"}}
            }
    }

    rule add_subscriptions {
        select when explicit add_subscriptions
        foreach ent:vehicles.keys() setting (key)
            event:send({
                "eci": meta:eci,
                "eid": "subscription",
                "domain": "wrangler",
                "type": "subscription",
                "attrs": {
                    "name": nameFromID(key),
                    "Rx_role": "fleet",
                    "Tx_role": "vehicle",
                    "channel_type": "subscription",
                    "wellKnown_Tx": ent:vehicles{[key, "eci"]}
                }
            })
    }

    rule clear_vehicles {
        select when clear vehicles
        always {
            ent:vehicles := {}
        }
    }
}