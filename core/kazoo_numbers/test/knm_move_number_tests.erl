%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2015-2020, 2600Hz
%%% @doc
%%% @author James Aimonetti
%%% @author Pierre Fenoll
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(knm_move_number_tests).

-export([db_dependant/0]).

-include_lib("eunit/include/eunit.hrl").
-include("../src/knm.hrl").

knm_create_new_number_test_() ->
    knm_test_util:start_db(fun db_dependant/0).

db_dependant() ->
    [move_to_child()
    ,acquire_parent_reserved()
    ,acquire_parent_reserved_failure()
    ,move_changing_public_fields()
    ,move_available_local()
    ,move_available_non_local()
    ].

move_to_child() ->
    [PN] = knm_pipe:succeeded(knm_ops:move([?TEST_AVAILABLE_NUM], ?CHILD_ACCOUNT_ID)),
    [?_assert(knm_phone_number:is_dirty(PN))
    ,{"verify assigned_to is child account"
     ,?_assertEqual(?CHILD_ACCOUNT_ID, knm_phone_number:assigned_to(PN))
     }
    ].

acquire_parent_reserved() ->
    Num = ?TEST_RESERVED_NUM,
    To = ?CHILD_ACCOUNT_ID,
    [PN0] = knm_pipe:succeeded(knm_ops:get([Num])),
    [PN1] = knm_pipe:succeeded(knm_ops:move([Num], To, [{auth_by, To}])),
    [PN2] = knm_pipe:succeeded(knm_ops:move([Num], To)),
    [?_assert(not knm_phone_number:is_dirty(PN0))
    ,{"verify test number is assigned to reseller"
     ,?_assertEqual(?RESELLER_ACCOUNT_ID, knm_phone_number:assigned_to(PN0))
     }
    ,{"verify test number is in the reserved state"
     ,?_assertEqual(?NUMBER_STATE_RESERVED, knm_phone_number:state(PN0))
     }
    ,?_assert(knm_phone_number:is_dirty(PN1))
    ,{"verify subaccount can assign parent reserved number"
     ,?_assertEqual(To, knm_phone_number:assigned_to(PN1))
     }
    ,{"verify subaccount transition to in_service"
     ,?_assertEqual(?NUMBER_STATE_IN_SERVICE, knm_phone_number:state(PN1))
     }
    ,?_assert(knm_phone_number:is_dirty(PN2))
    ,{"verify master account can assign reserved number"
     ,?_assertEqual(To, knm_phone_number:assigned_to(PN2))
     }
    ,{"verify master account transition to in_service"
     ,?_assertEqual(?NUMBER_STATE_IN_SERVICE, knm_phone_number:state(PN2))
     }
    ].

acquire_parent_reserved_failure() ->
    Num = ?TEST_RESERVED_NUM,
    To = ?UNRELATED_ACCOUNT_ID,

    [PN0] = knm_pipe:succeeded(knm_ops:get([Num])),
    [{Num, Error1}] = knm_pipe:failed_to_proplist(knm_ops:move([Num], To, [{'auth_by', To}])),
    [PN1] = knm_pipe:succeeded(knm_ops:move([Num], To)),

    [?_assert(not knm_phone_number:is_dirty(PN0))
    ,{"verify test number is assigned to reseller"
     ,?_assertEqual(?RESELLER_ACCOUNT_ID, knm_phone_number:assigned_to(PN0))
     }
    ,{"verify test number is in the reserved state"
     ,?_assertEqual(?NUMBER_STATE_RESERVED, knm_phone_number:state(PN0))
     }
    ,?_assert(knm_phone_number:is_dirty(PN1))
    ,{"verify master account can assign parent reserved number"
     ,?_assertEqual(To, knm_phone_number:assigned_to(PN1))
     }
    ,{"verify master account transition to in_service"
     ,?_assertEqual(?NUMBER_STATE_IN_SERVICE, knm_phone_number:state(PN1))
     }
    ,{"verify some random account cannot assign reserved number"
     ,?_assertEqual(<<"forbidden">>, knm_errors:error(Error1))
     }
    ].

move_changing_public_fields() ->
    Key = <<"my_key">>,
    Fields = [{<<"a">>, <<"bla">>}
             ,{Key, 42}
             ],
    Options = [{'public_fields', kz_json:from_list(Fields)}
               |knm_options:default()
              ],
    [PN0] = knm_pipe:succeeded(knm_ops:get([?TEST_AVAILABLE_NUM])),
    [PN] =  knm_pipe:succeeded(knm_ops:move([?TEST_AVAILABLE_NUM], ?RESELLER_ACCOUNT_ID, Options)),
    [?_assert(knm_phone_number:is_dirty(PN))
    ,{"verify a public key is set"
     ,?_assertEqual(<<"my string">>, public_value(Key, PN0))
     }
    ,{"verify that key got updated"
     ,?_assertEqual(42, public_value(Key, PN))
     }
    ,{"verify another key was added"
     ,?_assertEqual(<<"bla">>, public_value(<<"a">>, PN))
     }
    ,{"verify that that other key is really new"
     ,?_assertEqual('undefined', public_value(<<"a">>, PN0))
     }
    ].

public_value(Key, PN) ->
    kz_json:get_value(Key, knm_phone_number:to_public_json(PN)).


move_available_local() ->
    [PN0] = knm_pipe:succeeded(knm_ops:get([?TEST_AVAILABLE_NUM])),
    [?_assert(not knm_phone_number:is_dirty(PN0))
    ,{"Verify number is available"
     ,?_assertEqual(?NUMBER_STATE_AVAILABLE, knm_phone_number:state(PN0))
     }
    ,{"Verify an available number is unassigned"
     ,?_assertEqual('undefined', knm_phone_number:assigned_to(PN0))
     }
    ,?_assertEqual(?RESELLER_ACCOUNT_ID, knm_phone_number:prev_assigned_to(PN0))
    ,?_assertEqual([], knm_phone_number:reserve_history(PN0))
    ,?_assertEqual(?CARRIER_LOCAL, knm_phone_number:module_name(PN0))
    ,?_assertEqual([?FEATURE_LOCAL], knm_phone_number:features_list(PN0))
    ]
        ++ everyone_is_allowed_to_buy_local_available(?CHILD_ACCOUNT_ID, ?CHILD_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_local_available(?CHILD_ACCOUNT_ID, ?RESELLER_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_local_available(?CHILD_ACCOUNT_ID, ?MASTER_ACCOUNT_ID)

        ++ everyone_is_allowed_to_buy_local_available(?RESELLER_ACCOUNT_ID, ?CHILD_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_local_available(?RESELLER_ACCOUNT_ID, ?RESELLER_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_local_available(?RESELLER_ACCOUNT_ID, ?MASTER_ACCOUNT_ID)

        ++ everyone_is_allowed_to_buy_local_available(?MASTER_ACCOUNT_ID, ?CHILD_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_local_available(?MASTER_ACCOUNT_ID, ?RESELLER_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_local_available(?MASTER_ACCOUNT_ID, ?MASTER_ACCOUNT_ID)
        ++ [].

move_available_non_local() ->
    [PN0] = knm_pipe:succeeded(knm_ops:get([?TEST_AVAILABLE_NON_LOCAL_NUM])),
    [?_assert(not knm_phone_number:is_dirty(PN0))
    ,{"Verify number is available"
     ,?_assertEqual(?NUMBER_STATE_AVAILABLE, knm_phone_number:state(PN0))
     }
    ,{"Verify an available number is unassigned"
     ,?_assertEqual('undefined', knm_phone_number:assigned_to(PN0))
     }
    ,?_assertEqual(?RESELLER_ACCOUNT_ID, knm_phone_number:prev_assigned_to(PN0))
    ,?_assertEqual([], knm_phone_number:reserve_history(PN0))
    ,?_assertEqual(<<"knm_telnyx">>, knm_phone_number:module_name(PN0))
    ,?_assertEqual([], knm_phone_number:features_list(PN0))
    ]
        ++ everyone_is_allowed_to_buy_available(?CHILD_ACCOUNT_ID, ?CHILD_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_available(?CHILD_ACCOUNT_ID, ?RESELLER_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_available(?CHILD_ACCOUNT_ID, ?MASTER_ACCOUNT_ID)

        ++ everyone_is_allowed_to_buy_available(?RESELLER_ACCOUNT_ID, ?CHILD_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_available(?RESELLER_ACCOUNT_ID, ?RESELLER_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_available(?RESELLER_ACCOUNT_ID, ?MASTER_ACCOUNT_ID)

        ++ everyone_is_allowed_to_buy_available(?MASTER_ACCOUNT_ID, ?CHILD_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_available(?MASTER_ACCOUNT_ID, ?RESELLER_ACCOUNT_ID)
        ++ everyone_is_allowed_to_buy_available(?MASTER_ACCOUNT_ID, ?MASTER_ACCOUNT_ID)
        ++ [].

everyone_is_allowed_to_buy_local_available(AuthBy, AssignTo) ->
    Num = ?TEST_AVAILABLE_NUM,
    everyone_is_allowed_to_buy_available(Num, AuthBy, AssignTo, ?CARRIER_LOCAL, [?FEATURE_LOCAL]).
everyone_is_allowed_to_buy_available(AuthBy, AssignTo) ->
    Num = ?TEST_AVAILABLE_NON_LOCAL_NUM,
    everyone_is_allowed_to_buy_available(Num, AuthBy, AssignTo, <<"knm_telnyx">>, []).

everyone_is_allowed_to_buy_available(Num, AuthBy, AssignTo, Carrier, Features) ->
    [PN] = knm_pipe:succeeded(knm_ops:move([Num], AssignTo, [{auth_by,AuthBy}])),
    [?_assert(knm_phone_number:is_dirty(PN))
    ,?_assertEqual(Num, knm_phone_number:number(PN))
    ,{"Verify number is now in_service" ++ auth_and_assign(AuthBy, AssignTo)
     ,?_assertEqual(?NUMBER_STATE_IN_SERVICE, knm_phone_number:state(PN))
     }
    ,{"Verify number is now assigned" ++ auth_and_assign(AuthBy, AssignTo)
     ,?_assertEqual(AssignTo, knm_phone_number:assigned_to(PN))
     }
    ,?_assertEqual(?RESELLER_ACCOUNT_ID, knm_phone_number:prev_assigned_to(PN))
    ,?_assertEqual([], knm_phone_number:reserve_history(PN))
    ,?_assertEqual(Carrier, knm_phone_number:module_name(PN))
    ,?_assertEqual(Features, knm_phone_number:features_list(PN))
    ].

auth_and_assign(AuthBy, AssignTo) ->
    lists:flatten(
      [", auth_by/assign_to: "
      ,binary_to_list(binary:part(AuthBy, 0, 8))
      ,$/
      ,binary_to_list(binary:part(AssignTo, 0, 8))
      ]).
