ruleset manage_fleet {
    meta {
        name "Manage Fleet"
        description <<
            Lab 7 Manage Fleet
        >>
        author "Ryan Blaser"
        logging on
        use module io.picolabs.subscription alias Subscriptions
        share vehicles, entVehicles, generateReports, getLatestFiveReports
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
        generateReports = function() {
            // subs = {};
            // the_vehicles = Subscriptions:established("Tx_role","vehicle");
            // the_vehicles.klog("Vehicles: ");
            helper = function(subs, the_vehicles, count) {
                (count < the_vehicles.length()) => helper2(subs, the_vehicles, count)
                                                | subs
            };
            helper2 = function(subs, the_vehicles, count) {
              report = generateReport(the_vehicles{[count, "Tx"]});
              report.klog("Report value ");
              subs = subs.put(count, report).klog("Subs now has value ");
              helper(subs, the_vehicles, count + 1)
            };
            helper({}, Subscriptions:established("Tx_role","vehicle"), 0)
        }
        generateReport = function(eci) {
            url = meta:host + "/sky/cloud/" + eci + "/trip_store/trips";
            response = http:get(url, {});
            response["content"]
        }
        getLatestFiveReports = function() {
            ent:reports
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
    
    rule generate_report {
      select when car generate_report
      pre {
        num_subs = Subscriptions:established("Tx_role","vehicle").length()
        reportId = "Report " + random:uuid()
      }
      always {
        ent:reports := ent:reports.defaultsTo({}, "initialized ent:reports");
        ent:reports := ent:reports.put([reportId], {
            "vehicles" : num_subs,
            "responding" : 0,
            "trips" : [],
            "timestamp" : time:now()
        });
        raise explicit event "generate_report" attributes {
            "reportId" : reportId
        }
      }
    }

    rule explicit_generate_report {
        select when explicit generate_report
        foreach Subscriptions:established("Tx_role","vehicle") setting(subscription)
            pre {
                reportId = event:attr("reportId")
                thing_subs = subscription.klog("vehicle")
            }
            event:send({
                "eci": subscription{"Tx"},
                "eid": "generate_report",
                "domain": "car",
                "type": "generate_report",
                "attrs": {
                    "reportId" : reportId
                }
            })
    }

    rule receive_report {
        select when car receive_report
        pre {
            report = event:attr("report")
            reportId = event:attr("reportId")
            reports = ent:reports{[reportId]}
        }
        always {
            reports["responding"] = reports["responding"] + 1;
            reports["trips"].append(report);
            ent:reports := reports;
            raise explicit event "return_report" attributes {
                "reportId" : reportId
            } if (reports["vehicles"] == reports["responding"]);
        }
    }

    rule return_report {
        select when explicit return_report
        pre {
            reportId = event:attr("reportId")
            report = ent:reports{[reportId]}
        }
        send_directive("report", report)
    }

    rule clear_vehicles {
        select when clear vehicles
        always {
            ent:vehicles := {}
        }
    }
}