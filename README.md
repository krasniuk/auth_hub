auth_hub
=====

Build
-----

Start service


    $ make rel
    $ ./_build/prod/rel/auth_hub/bin/auth_hub console

    or

    $ ./run_main.sh

Start (Common tests + EUnit tests)


    $ rebar3 ct --spec apps/auth_hub/tests/test.spec

Start WRK

    $ wrk -t500 -c500 -d5s -s apps/auth_hub/wrk/stress_test_admin_api.lua http://127.0.0.1:1913
    $ wrk -t500 -c500 -d5s -s apps/auth_hub/wrk/stress_test_client_api.lua http://127.0.0.1:1913
    
API
----

open session

    POST http://127.0.0.1:1913/session/open
    Content-Type: application/json
    {
        "login": "admin",
        "pass": "12345678"
    }  
    
    - response 200 -
    {
        "success": {
            "sid": "3c552a129a4711ef884b18c04d540e8a",
            "ts_end": "2024-11-04 03:23:41",
            "ts_start": "2024-11-04 02:53:41"
        }
    }
    
check sid

    GET http://127.0.0.1:1913/session/check?sid=6cf1751a9da611ef8a7918c04d540e8a
    Content-Type: application/json
    
    - response 200 -
    {
        "success": {
            "active_session": true
        }
    }

get login

    GET http://127.0.0.1:1913/identification/login
    Content-Type: application/json
    sid: fdfdb23a9d4211efb25d18c04d540e8a
    
    - response 200 -
    {
        "success": {
            "login": "admin"
        }
    }

get roles (case authHub)

    POST http://127.0.0.1:1913/authorization/roles
    Content-Type: application/json
    sid: fdfdb23a9d4211efb25d18c04d540e8a
    {
        "subsystem": "authHub"
    }

    - response 200 -
    {
    "success": {
        "space_roles": {
            "authHub": [
                "am"
            ],
            "testSubsys": [
                "am"
            ]
        },
        "subsystem": "authHub"
    }
    }

get roles (other)

    POST http://127.0.0.1:1913/authorization/roles
    Content-Type: application/json
    sid: fdfdb23a9d4211efb25d18c04d540e8a
    {
        "subsystem": "mainBroker"
    }

    - response 200 -
    {
    "success": {
        "roles": [
            "am",
            "cr"
        ],
        "subsystem": "authHub"
    }
    }

create users

    POST http://127.0.0.1:1913/api/users
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
        "method": "create_users",
        "users": [
            {
                "login": "kv190901kma",
                "pass": "22222222"
            }
        ]
    }

    - response 200 -
    {
        "users": [
            {
                "login": "kv190901kma",
                "success": true
            }
        ]
    }

delete users

    POST http://127.0.0.1:1913/api/users
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
        "method": "delete_users",
        "logins": ["MissL", "Mr_L"]
    }

    - response 200 -
    {
        "users": [
            {
                "login": "MissL",
                "success": true
            },
            {
                "login": "Mr_L",
                "success": true
            }
        ]
    }

get all users info
(subsystem authHub has spaces "success" -> "info" -> "subsystem_roles" -> "authHub"(subsystem) -> "authHub"(space) -> "am"(role))

    GET http://127.0.0.1:1913/api/users/info
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    
    - response 200 -
    {
    "success": {
        "info": [
            {
                "has_activ_sid": true,
                "login": "admin",
                "subsystem_roles": {
                    "authHub": {
                        "authHub": [
                            "am"
                        ],
                        "bigBag": [
                            "am"
                        ],
                        "mainBroker": [
                            "am"
                        ],
                        "testSubsys": [
                            "am"
                        ]
                    },
                    "bigBag": [],
                    "mainBroker": [],
                    "testSubsys": []
                }
            },
            {
                "has_activ_sid": true,
                "login": "broker",
                "subsystem_roles": {
                    "authHub": {
                        "authHub": [],
                        "bigBag": [],
                        "mainBroker": [
                            "am"
                        ],
                        "testSubsys": []
                    },
                    "bigBag": [],
                    "mainBroker": [],
                    "testSubsys": []
                }
            }
        ]
    }
    }

get allow subsystems roles

    GET http://127.0.0.1:1913/api/allow/subsystems/roles/info
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a

    - response 200 -
    {
    "success": {
        "info": [
            {
                "allow_roles": [
                    {
                        "description": "All admin roles",
                        "role": "am"
                    },
                    {
                        "description": "Delete user roles",
                        "role": "dr"
                    },
                    {
                        "description": "Add roles for user",
                        "role": "ar"
                    },
                    {
                        "description": "Delete users",
                        "role": "dl"
                    },
                    {
                        "description": "Create users",
                        "role": "cr"
                    }
                ],
                "description": "Service auth_hub",
                "subsystem": "authHub"
            },
            {
                "allow_roles": [
                    {
                        "description": "Administrator - all roles",
                        "role": "am"
                    }
                ],
                "description": "Service main_broker",
                "subsystem": "mainBroker"
            },
            {
                "allow_roles": [],
                "description": "Service where application save data",
                "subsystem": "bigBag"
            }
        ]
    }
    }

add roles 

    POST http://127.0.0.1:1913/api/roles/change
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
    "method": "add_roles",
    "changes": [
        {
            "login": "kv190901kma",
            "subsystem": "authHub",
            "roles": ["cr", "dl"]
        },
        {
            "login": "dn190901kma",
            "subsystem": "authHub",
            "roles": ["cr", "dl"]
        }
    ]
    }

    - response 200 -
    {
    "results": [
        {
            "login": "kv190901kma",
            "roles": [
                "cr",
                "dl"
            ],
            "subsystem": "authHub",
            "success": true
        },
        {
            "login": "dn190901kma",
            "roles": [
                "cr",
                "dl"
            ],
            "subsystem": "authHub",
            "success": true
        }
    ]
    }

remove roles

    POST http://127.0.0.1:1913/api/roles/change
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
    "method": "remove_roles",
    "changes": [
        {
            "login": "kv190901kma",
            "subsystem": "authHub",
            "roles": ["cr", "dl"]
        },
        {
            "login": "dn190901kma",
            "subsystem": "authHub",
            "roles": ["cr", "dl"]
        }
    ]
    }

    - response 200 -
    {
    "results": [
        {
            "login": "kv190901kma",
            "roles": [
                "cr",
                "dl"
            ],
            "subsystem": "authHub",
            "success": true
        },
        {
            "login": "dn190901kma",
            "roles": [
                "cr",
                "dl"
            ],
            "subsystem": "authHub",
            "success": true
        }
    ]
    }

create roles

    POST http://127.0.0.1:1913/api/allow/roles/change
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
    "method": "create_roles",
    "roles": [
        {
            "role": "tq",
            "subsystem": "authHub",
            "description": "test role"
        }
    ]
    }

    - response 200 -
    {
    "results": [
        {
            "role": "tq",
            "subsystem": "authHub",
            "success": true
        }
    ]
    }

delete allow roles

    POST http://127.0.0.1:1913/api/allow/roles/change
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
    "method": "delete_roles",
    "subsys_roles": {
        "authHub": ["cl", "dl"],
        "mainBroker": ["rk", "kr"]
    }
    }

    - response 200 -
    {
    "results": [
        {
            "role": "cl",
            "subsystem": "authHub",
            "success": true
        },
        {
            "role": "dl",
            "subsystem": "authHub",
            "success": true
        },
        {
            "role": "rk",
            "subsystem": "mainBroker",
            "success": true
        },
        {
            "role": "kr",
            "subsystem": "mainBroker",
            "success": true
        }
    ]
    }

create subsystems

    POST http://127.0.0.1:1913/api/allow/subsystems/change
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
    "method": "create_subsystems",
    "subsystems": [
        {
            "subsystem": "test3",
            "description": "test sumsystem"
        },
        {
            "subsystem": "test2",
            "description": "test sumsystem"
        }
    ]
    }

    - response 200 -
    {
    "results": [
        {
            "subsystem": "test3",
            "success": true
        },
        {
            "reason": "role exists",
            "subsystem": "test2",
            "success": false
        }
    ]
    }

delete subsystems 

    POST http://127.0.0.1:1913/api/allow/subsystems/change
    Content-Type: application/json
    sid: 7a9bdcfea34c11ef801c18c04d540e8a
    {
        "method": "delete_subsystems",
        "subsystems": ["test", "authHub"]
    }

    - response 200 -
    {
    "results": [
        {
            "subsystem": "test",
            "success": true
        },
        {
            "reason": "root subsystem",
            "subsystem": "authHub",
            "success": false
        }
    ]
    }




PgSql Create scripts
----
Tables
---
allow_roles

    CREATE TABLE public.allow_roles (
        subsystem varchar NOT NULL,
        "role" varchar NOT NULL,
        description varchar NULL,
        CONSTRAINT allow_roles_pkey PRIMARY KEY (subsystem, role),
        CONSTRAINT c1 FOREIGN KEY (subsystem) REFERENCES public.allow_subsystems(subsystem)
    );

allow_subsystems

    CREATE TABLE public.allow_subsystems (
	    subsystem varchar NOT NULL,
	    description varchar NULL,
	    CONSTRAINT allow_subsystems_pkey PRIMARY KEY (subsystem)
    );

roles

    CREATE TABLE IF NOT EXISTS public.roles
    (
        login character varying(50) COLLATE pg_catalog."default" NOT NULL,
        subsystem character varying(10) COLLATE pg_catalog."default" NOT NULL,
        role character varying(10) COLLATE pg_catalog."default" NOT NULL,
        CONSTRAINT roles_pkey PRIMARY KEY (login, subsystem, role),
        CONSTRAINT const_1 FOREIGN KEY (role, subsystem)
            REFERENCES public.allow_roles (role, subsystem) MATCH SIMPLE
            ON UPDATE NO ACTION
            ON DELETE NO ACTION
            NOT VALID,
        CONSTRAINT const_2 FOREIGN KEY (login)
            REFERENCES public.users (login) MATCH SIMPLE
            ON UPDATE NO ACTION
            ON DELETE NO ACTION
            NOT VALID
    )

    TABLESPACE pg_default;

    ALTER TABLE IF EXISTS public.roles
        OWNER to admin;

sids

    CREATE TABLE public.sids (
	    login varchar NOT NULL,
	    sid varchar NOT NULL,
	    ts_end timestamp NOT NULL,
	    CONSTRAINT sids_pkey PRIMARY KEY (login),
	    CONSTRAINT "unique" UNIQUE (sid),
	    CONSTRAINT const1 FOREIGN KEY (login) REFERENCES public.users(login)
    );

users

    CREATE TABLE public.users (
	    login varchar(50) NOT NULL,
	    passhash varchar(100) NOT NULL,
	    CONSTRAINT login_pk PRIMARY KEY (login),
	    CONSTRAINT unique_pass UNIQUE (passhash)
    );


Functions
---

delete_user(varchar)

    CREATE OR REPLACE FUNCTION public.delete_user(login_i character varying)
        RETURNS character varying
        LANGUAGE plpgsql
    AS $function$#variable_conflict use_column
    BEGIN

	    DELETE FROM roles WHERE login=login_i;
	    DELETE FROM sids WHERE login=login_i;
	    DELETE FROM users WHERE login=login_i;
	    RETURN 'ok';

    END;$function$
    ;

delete_allow_role(varchar, varchar)

    CREATE OR REPLACE FUNCTION public.delete_allow_role(subsystem_i character varying, role_i character varying)
	    RETURNS character varying
 	    LANGUAGE plpgsql
    AS $function$#variable_conflict use_column
        BEGIN

	    DELETE FROM roles WHERE role=role_i and subsystem=subsystem_i;
	    DELETE FROM allow_roles WHERE role=role_i and subsystem=subsystem_i;
	    RETURN 'ok';
	
	    END;
    $function$
    ;

delete_subsystem(varchar)

    CREATE OR REPLACE FUNCTION public.delete_subsystem(subsystem_i character varying)
 	    RETURNS character varying
 	    LANGUAGE plpgsql
    AS $function$#variable_conflict use_column
        BEGIN

	    DELETE FROM roles WHERE space=subsystem_i;
	    DELETE FROM allow_roles WHERE subsystem=subsystem_i;
	    DELETE FROM allow_subsystems WHERE subsystem=subsystem_i;
	    RETURN 'ok';

	    END;
    $function$
    ;

create_subsystem(varchar, varchar)

    CREATE OR REPLACE FUNCTION public.create_subsystem(subsystem_i character varying, description_i character varying)
        RETURNS character varying
        LANGUAGE plpgsql
    AS $function$#variable_conflict use_column
        BEGIN

	    insert into allow_subsystems (subsystem, description) values (subsystem_i, description_i);
	    insert into roles (login, role, subsystem, space) values ('admin', 'am', 'authHub', subsystem_i);
	    RETURN 'ok';
	
	    END;
    $function$
    ;
