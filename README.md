acl_simple
=====

An OTP application

Build
-----

    $ rebar3 compile
    "or"
    $ ./run.sh


    
Data developer
================    
    Transmission base: http, POST.
    Transmission format: json.

    Roles: "read", "write", "exec".

    Cache saves in ets. Table 'acl_simple' in key 'server_cache'. 

API
-----
    acl_simple_server:
        State = #{<<"User">> => [<<"Role">>, ..], ..},
    
        handle_call:
            user_add({user_add, <<"NewUser">>}),                          (127 ms) | (106 ms) <- with cache
            user_delete({user_delete, <<"User">>}),                       (271 ms) | (297 ms)
            show_all_users({show_all_users}),                             (114 ms) | (2 ms)
        
            roles_add({roles_add, <<"User">>, [<<"Role">>, ...]}),        (459 ms) | (246 ms)
            roles_delete({roles_delete, <<"User">>, [<<"Role">>, ...]}),  (185 ms) | (208 ms)
            show_roles({show_roles, <<"User">>}),                         (185 ms) | (2 ms)
        
            show_allow_roles({show_allow_roles}).                         (1 ms)   | (1 ms)

        
JSON reqests options
-----
{
    "method":"user_add",
    "user":"Joe",
    "roles":["read", "exec"]
}


