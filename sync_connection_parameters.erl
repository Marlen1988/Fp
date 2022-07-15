-module(new_sync).

-include("fp_struct.hrl").

-export([on_event/2]).
-export([
  create_table/2,
  reservation/2,
  telemetry/2
]).


%%Only for test purposes
-export([
  make_batch_test/2
]).

%Some changes happened here%
% Now we work with seconds, not milliseconds%
-define(HOUR, 3600).
-define(DAY, 24 * ?HOUR).
-define(STEP, 1000).
-define(DUMMY, 0).
-define(SECOND, 1000).
-define(I2L(Int), add(Int)).
-define(PREFIX, 19).
-define(BATCH, 600).
-define(TS1970, 62167219200).

on_event({on_cycle,_Cycle},State)->
  % here should be your code that is executed each Cycle milliseconds
  State;
on_event({tag,_TagID,_Field,_Value},State)->
  % here should be your code that is executed on change of the Field of the Tag
  State.

create_table(Path, Ref)->
  {_, Result} = fp_db:query(<<"get .name, .pattern from root where .folder=$oid('", Path/binary,"')">>),
  ?LOGINFO("Result ~p", [Result]),
  ColumnsPreProc = [ begin
                       NewName = transform_name(Name),
                       binary_to_list(NewName) ++ " REAL"
                     end
    || [Name, Pattern]<-Result,  fp_db:to_path(Pattern) == <<"/root/.patterns/ARCHIVE">>],
  Columns1 =  ["timestamp timestamp" | ColumnsPreProc ],
  case Columns1 of
    [_] ->
      ok;
    _ ->
      Columns =  lists:append( lists:join(",", Columns1)),
      <<"/root/PROJECT/TAGS/", TableName1/binary>> = Path,
      TableName = binary_to_list( binary:replace(TableName1, [<<"/">>, <<"-">>], <<"_">>, [global]) ),
      CreateQuery = "CREATE TABLE IF NOT EXISTS " ++ TableName ++ " (" ++ Columns ++ ")",
      odbc:sql_query(Ref, CreateQuery),
      IndexName = "ts_" ++ TableName,
      CreateIndex = "CREATE INDEX IF NOT EXISTS " ++ IndexName ++ " ON " ++ TableName ++ " (timestamp)",
      odbc:sql_query(Ref, CreateIndex)
  end,
  [create_table(<<Path/binary, "/", Name/binary>>, Ref) || [Name, Pattern] <-Result, fp_db:to_path(Pattern) /= <<"/root/.patterns/ARCHIVE">>],
  ok.


reservation(Path, Ref) ->
  {_, Result} = fp_db:query(<<"get .name, .path, .pattern from root where .folder=$oid('", Path/binary,"')">>),
  <<"/root/PROJECT/TAGS/", TableName1/binary>> = Path,
  TableName = binary_to_list( binary:replace(TableName1, [<<"/">>, <<"-">>], <<"_">>, [global]) ),
  ArchivesData = [[Name, APath] || [Name, APath, Pattern] <- Result, fp_db:to_path(Pattern) == <<"/root/.patterns/ARCHIVE">>],
  case ArchivesData of
    []->
      ok;
    _->
      add_columns(Ref, TableName, ArchivesData),
      Archives = [[APath, avg] ||[_Name, APath]<-  ArchivesData],
      {selected, _, [{MaxTS}] } = odbc:sql_query(Ref, "SELECT MAX(timestamp) FROM " ++ TableName),
      Columns = ["timestamp" | [ binary_to_list(transform_name(Name)) ||[Name, _APath]<- ArchivesData] ],

      insert_by_batch(Ref, TableName, Archives, Columns, MaxTS)

  end,
  [reservation(FPath, Ref) ||[Name, FPath,Pattern]<- Result, fp_db:to_path(Pattern) /= <<"/root/.patterns/ARCHIVE">> ],
  ok.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% New function for writing data to postgres %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
insert_by_batch(Ref, TableName, Archives, Columns, MaxTS) ->
  telemetry("########## Table ~p ########",[TableName]),
  CurrentTS = erlang:system_time(seconds) * 1000,
  BatchPoints =
    case MaxTS of
      null ->
        [ lists:seq(CurrentTS - ?SECOND, CurrentTS, ?STEP) ];
      _ ->
        ?LOGINFO("MaxTS is ~p for table ~p", [MaxTS, TableName]),
        MaxTS1 = from_dt_to_ts(MaxTS) * 1000,
        telemetry("MaxTS ~p ~p, CurrentTS ~p, TableName ~p", [MaxTS, MaxTS1, CurrentTS, TableName]),
        if
          %we need this for ease of implementation 'make_batch'%
          MaxTS1 < CurrentTS ->
            Points = lists:reverse( lists:seq(MaxTS1, CurrentTS, ?STEP) ),
            telemetry("TimePoints number ~p, TableName ~p", [length(Points), TableName]),
            make_batch(Points);
          true -> []
        end
    end,
  ?LOGINFO("Archives ~p", [Archives]),


  WriteBatch =
    fun(Points) ->
      Data = fp:archives_get(Points, Archives),
      telemetry("BathSize ~p, TableName ~p", [length(Data), TableName]),
      case Data of
        [] -> ok;
        Data ->
          %   ?LOGINFO("Data ~p", [Data]),
          TransposedData= fp_lib:transpose(Data),
          ReplacedTransposedData = replace_none(TransposedData),
          insert(ReplacedTransposedData, TableName, Columns, Ref)
      end
    end,
  case BatchPoints of
    [] -> ok;
    _ -> lists:foreach(WriteBatch, BatchPoints)
  end,
  telemetry("########## Table ~p ########",[TableName]),
  ok.

%%%%%%%%%%%%%%%%%%%%
% internal helpers %
%%%%%%%%%%%%%%%%%%%%
%Data = [[TS1, TS2, TS3, ...], [Col1Values...], [Col2Values...]],
%Columns = [Col1, Col2, ...],
insert(Data, TableName, Columns, Ref) ->
  {ok, DataTypes1} = odbc:describe_table(Ref, TableName),
  Mapping = maps:from_list(DataTypes1),
  ColumnNum = length(Data),
  [TsLists | RestData] = Data,
  DateTimeList = [ calendar:system_time_to_local_time(TS div 1000, second) ||TS<- TsLists],
  NewData = [DateTimeList | RestData],
  %NewData =  lists:sublist(Data, 2, ColNum),

  ValuesStr = "VALUES (" ++ lists:append( lists:join(",",  ["?" || _ <- lists:seq(1, ColumnNum)]) ) ++ ")",
  ColumnsStr =  " (" ++   lists:append( lists:join(",",  Columns))   ++ ") ",
  InsertQuery = "INSERT INTO " ++ TableName ++ ColumnsStr ++ ValuesStr,

  ?LOGINFO("query ~p", [InsertQuery]),


  InsertData = [
    begin
      Type = maps:get(ColName, Mapping),
      {Type, ColumnData}
    end
    || {ColName, ColumnData} <- lists:zip(Columns, NewData)],
%%  ?LOGINFO("InsertData: ~p", [ InsertData]),
  QueryResp = odbc:param_query(Ref, InsertQuery, InsertData),
  telemetry("QueryRespond ~p", [QueryResp]),
  ?LOGINFO("After query"),
  ok.


replace_none([TS|Data]) ->
  ReplacedData=
    [[begin
        case Value of
          none -> null;
          _->Value
        end
      end ||Value<-ArchiveData]
      || ArchiveData<-Data],
  [TS|ReplacedData].


from_dt_to_ts({{_Year, _Month, _Day}, {_Hour, _Minute, _Second}}=DT) ->
  DT1 = calendar:local_time_to_universal_time(DT),
  calendar:datetime_to_gregorian_seconds(DT1) - ?TS1970.
%%  StringData = ?I2L(Year) ++ "-" ++ ?I2L(Month) ++ "-" ++ ?I2L(Day) ++ " " ++ ?I2L(Hour) ++ ":" ++ ?I2L(Minute) ++ ":" ++ ?I2L(Second) ++ "+06:00",
%%  calendar:rfc3339_to_system_time(StringData, [{unit, second}]).

add(Int) ->
  LstTime = integer_to_list(Int),
  if
    length(LstTime) < 2 -> "0" ++ LstTime;
    true -> LstTime
  end.

transform_name(ArchiveName) ->
  Name = string:trim(ArchiveName),
  <<H:1/binary, _Rest/binary>> = Name,
  Head =
    if
      <<"0">> =< H, H =< <<"9">> -> <<"_">>;
      true -> <<>>
    end,
  NewName = binary:replace(Name, [<<"-">>, <<" ">>], <<"_">>, [global]),
  string:casefold(<<Head/binary, NewName/binary>>).

add_columns(Ref, TableName, ArchivesData) ->
  Archives = [ binary_to_list(transform_name(Name)) ||[Name, _APath]<- ArchivesData],
  Query = "SELECT * FROM " ++ TableName ++ " WHERE false",
  {selected, PostgreColumns, _} = odbc:sql_query(Ref, Query),
  CreateColumns = Archives -- PostgreColumns,
  case CreateColumns of
    [] -> ok;
    CreateColumns ->
      QueryPart = lists:append( lists:join(",", ["ADD COLUMN IF NOT EXISTS " ++ ColName ++ " REAL"||ColName <- CreateColumns]) ),
      AddColQuery = "ALTER TABLE " ++ TableName ++ " " ++ QueryPart,
      ?LOGINFO("Added columns ~p", [AddColQuery]),
      {updated, _} = odbc:sql_query(Ref, AddColQuery)
  end,
  ok.


telemetry(Format, Params) ->
  try
    PrivDir = code:priv_dir(fp),
    LogFile = PrivDir ++ "/telemetry.txt",
    TelemetryStr = list_to_binary( io_lib:format(Format, Params) ),
    file:write_file(LogFile, <<TelemetryStr/binary, "\n">>, [append])
  catch
      _:Error  -> ?LOGERROR("Cannot log telemetry, error: ~p", [Error])
  end,
  ok.


make_batch(Points) ->
  make_batch(Points, [], [], 0).
make_batch([], Current, Acc, _Counter) ->
  [Current | Acc];
make_batch([P|Points], Current, Acc, Counter) ->
  if
    Counter < ?BATCH-> make_batch(Points, [P|Current], Acc, Counter + 1);
  % We add Point 'P' to Current because when we read data from archive we ignore first point
  % Ex: we need this [TS1, TS2, TS3] -> [Value1, Value2, Value3]
  % but fp_archive:get([TS1, TS2, TS3], Archives) -> [Value2, Value3], so we need TS0
  % fp_archive:get([TS0, TS1, TS2, TS3], Archives) -> [Value1, Value2, Value3]
    Counter == ?BATCH -> make_batch(Points, [P], [[P | Current] | Acc], 1)
  end.


make_batch_test(Points, BatchSize) ->
  make_batch_test(Points, BatchSize, [], [], 0).
make_batch_test([], _BatchSize, Current, Acc, _Counter) ->
  [Current | Acc];
make_batch_test([P|Points], BatchSize, Current, Acc, Counter) ->
  if
    Counter < BatchSize-> make_batch_test(Points, BatchSize, [P|Current], Acc, Counter + 1);
  % We add Point 'P' to Current because when we read data from archive we ignore first point
  % Ex: we need this [TS1, TS2, TS3] -> [Value1, Value2, Value3]
  % but fp_archive:get([TS1, TS2, TS3], Archives) -> [Value2, Value3], so we need TS0
  % fp_archive:get([TS0, TS1, TS2, TS3], Archives) -> [Value1, Value2, Value3]
    Counter == BatchSize -> make_batch_test(Points, BatchSize, [P], [[P | Current] | Acc], 1)
  end.

