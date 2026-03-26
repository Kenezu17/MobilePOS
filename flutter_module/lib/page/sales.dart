import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hidden_drawer_menu/controllers/simple_hidden_drawer_controller.dart';

import '../app_settings.dart';

// ─────────────────────────────────────────────────────────────
// DARK/LIGHT TOKENS
// ─────────────────────────────────────────────────────────────

Color _c(bool d, Color l, Color dk) => d ? dk : l;

abstract class _D {
  static const bg      = Color(0xFF1A0F0A);
  static const surface = Color(0xFF2C1A10);
  static const card    = Color(0xFF3A2318);
  static const text    = Color(0xFFF5EDE4);
  static const sub     = Color(0xFFB08B72);
  static const accent  = Color(0xFFD4A373);
}

// ─────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────

enum SalesFilter { today, week, month, all }
extension SalesFilterLabel on SalesFilter {
  String get label => switch(this){
    SalesFilter.today => 'Today', SalesFilter.week  => 'This Week',
    SalesFilter.month => 'This Month', SalesFilter.all => 'All Time',
  };
}

enum GraphRange { week, month, year }
extension GraphRangeLabel on GraphRange {
  String get label => switch(this){
    GraphRange.week  => '7 Days', GraphRange.month => '30 Days',
    GraphRange.year  => '12 Months',
  };
}

// ─────────────────────────────────────────────────────────────
// SALES PAGE
// ─────────────────────────────────────────────────────────────

class Sales extends StatefulWidget {
  const Sales({super.key});
  @override State<Sales> createState() => _SalesState();
}

class _SalesState extends State<Sales> {
  final _db         = FirebaseFirestore.instance;
  final _auth       = FirebaseAuth.instance;
  final _searchCtrl = TextEditingController();

  SalesFilter _filter     = SalesFilter.today;
  GraphRange  _graphRange = GraphRange.week;
  String      _payFilter  = 'All';
  late Stream<QuerySnapshot> _salesStream;

  String get _uid => _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _salesStream = _db
        .collection('users').doc(_uid).collection('sales')
        .orderBy('createdAt', descending: true).snapshots();
  }

  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  DateTime get _fromDate {
    final now = DateTime.now();
    return switch(_filter){
      SalesFilter.today => DateTime(now.year,now.month,now.day),
      SalesFilter.week  => now.subtract(const Duration(days:7)),
      SalesFilter.month => DateTime(now.year,now.month,1),
      SalesFilter.all   => DateTime(2000),
    };
  }

  List<Map<String,dynamic>> _applyFilters(List<Map<String,dynamic>> sales){
    final q = _searchCtrl.text.trim().toLowerCase();
    return sales.where((s){
      if(_payFilter!='All'){
        final m=(s['paymentMethod']??'').toString().toLowerCase();
        if(_payFilter=='Cash'  && m!='cash')  return false;
        if(_payFilter=='GCash' && m!='gcash') return false;
      }
      if(q.isNotEmpty){
        final id=(s['orderId']??'').toString().toLowerCase();
        if(!id.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  List<_GraphPoint> _buildGraphPoints(List<Map<String,dynamic>> all){
    final now=DateTime.now();
    switch(_graphRange){
      case GraphRange.week:
        return List.generate(7,(i){
          final day=now.subtract(Duration(days:6-i));
          final ds=DateTime(day.year,day.month,day.day);
          final de=ds.add(const Duration(days:1));
          final t=all.where((s){
            final ts=(s['createdAt'] as Timestamp?)?.toDate();
            return ts!=null&&ts.isAfter(ds)&&ts.isBefore(de);
          }).fold<int>(0,(sum,s)=>sum+((s['total']??0) as int));
          return _GraphPoint(label:_day(day.weekday),value:t.toDouble());
        });
      case GraphRange.month:
        return List.generate(4,(i){
          final we=now.subtract(Duration(days:i*7));
          final ws=we.subtract(const Duration(days:7));
          final t=all.where((s){
            final ts=(s['createdAt'] as Timestamp?)?.toDate();
            return ts!=null&&ts.isAfter(ws)&&ts.isBefore(we);
          }).fold<int>(0,(sum,s)=>sum+((s['total']??0) as int));
          return _GraphPoint(label:'W${4-i}',value:t.toDouble());
        });
      case GraphRange.year:
        return List.generate(12,(i){
          final md=DateTime(now.year,now.month-(11-i),1);
          final me=DateTime(md.year,md.month+1,1);
          final t=all.where((s){
            final ts=(s['createdAt'] as Timestamp?)?.toDate();
            return ts!=null&&ts.isAfter(md)&&ts.isBefore(me);
          }).fold<int>(0,(sum,s)=>sum+((s['total']??0) as int));
          return _GraphPoint(label:_mon(md.month),value:t.toDouble());
        });
    }
  }

  String _day(int w)=>['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][w-1];
  String _mon(int m)=>['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m-1];

  @override
  Widget build(BuildContext context){
    final d   = AppSettings.of(context).darkMode;
    final bg  = _c(d, const Color(0xFFF6F6F6), _D.bg);
    final cardBg = _c(d, const Color(0xFFFDF6F1), _D.card);
    final text   = _c(d, const Color(0xFF2C1A0E), _D.text);
    final sub    = _c(d, Colors.grey.shade500,    _D.sub);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(child: Column(children:[
        _Topbar(isDark:d, onMenuTap:()=>SimpleHiddenDrawerController.of(context).toggle()),
        Expanded(child: StreamBuilder<QuerySnapshot>(
            stream:_salesStream,
            builder:(context,snap){
              if(snap.hasError) return Center(child:Text('Error: ${snap.error}'));
              if(snap.connectionState==ConnectionState.waiting)
                return Center(child:CircularProgressIndicator(color:_c(d,const Color(0xFF4E342E),_D.accent)));

              final all=snap.data!.docs.map((d)=>d.data() as Map<String,dynamic>).toList();
              final ft=Timestamp.fromDate(_fromDate);
              final dateSales=all.where((s){
                final ts=s['createdAt'] as Timestamp?;
                return ts!=null&&ts.compareTo(ft)>=0;
              }).toList();

              final filtered=_applyFilters(dateSales);
              final pts=_buildGraphPoints(all);
              final rev=dateSales.fold<int>(0,(s,e)=>s+((e['total']??0) as int));
              final cash=dateSales.where((s)=>(s['paymentMethod']??'')=='cash').length;
              final gcash=dateSales.where((s)=>(s['paymentMethod']??'')=='gcash').length;

              return SingleChildScrollView(
                  physics:const BouncingScrollPhysics(),
                  keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.onDrag,
                  child:Column(children:[
                    _SummaryBanner(filter:_filter, totalRevenue:rev,
                        totalOrders:dateSales.length, cashOrders:cash, gcashOrders:gcash),
                    _FilterTabs(selected:_filter, isDark:d, onSelected:(f)=>setState(()=>_filter=f)),
                    _GraphCard(points:pts, range:_graphRange, isDark:d,
                        onRange:(r)=>setState(()=>_graphRange=r)),

                    Padding(padding:const EdgeInsets.fromLTRB(18,20,18,8),
                        child:Center(child:Text('Recent Transactions',
                            style:TextStyle(fontSize:15,fontWeight:FontWeight.w800,
                                color:_c(d,const Color(0xFF4E342E),_D.accent))))),

                    Padding(padding:const EdgeInsets.fromLTRB(18,0,18,30),
                        child:Container(
                            decoration:BoxDecoration(
                                color:cardBg,
                                borderRadius:BorderRadius.circular(22),
                                boxShadow:[BoxShadow(
                                    color:const Color(0xFF4E342E).withOpacity(d?0.2:0.05),
                                    blurRadius:16, offset:const Offset(0,6))]),
                            child:Column(children:[
                              Padding(padding:const EdgeInsets.all(14),
                                  child:Row(children:[
                                    Expanded(child:Container(
                                        height:44,
                                        decoration:BoxDecoration(
                                            color:_c(d,Colors.white,_D.surface),
                                            borderRadius:BorderRadius.circular(14)),
                                        child:TextField(
                                          controller:_searchCtrl,
                                          onChanged:(_)=>setState((){}),
                                          style:TextStyle(fontSize:13,color:text),
                                          decoration:InputDecoration(
                                              hintText:'Search order ID...',
                                              hintStyle:TextStyle(color:sub,fontSize:13),
                                              prefixIcon:Icon(Icons.search,size:18,color:sub),
                                              border:InputBorder.none,
                                              contentPadding:const EdgeInsets.symmetric(vertical:12)),
                                        ))),
                                    const SizedBox(width:10),
                                    Container(
                                        height:44,
                                        padding:const EdgeInsets.symmetric(horizontal:12),
                                        decoration:BoxDecoration(
                                            color:_c(d,Colors.white,_D.surface),
                                            borderRadius:BorderRadius.circular(14)),
                                        child:DropdownButtonHideUnderline(child:DropdownButton<String>(
                                          value:_payFilter,
                                          dropdownColor:_c(d,Colors.white,_D.card),
                                          style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:text),
                                          icon:Icon(Icons.expand_more,size:18,color:sub),
                                          items:['All','Cash','GCash'].map((v)=>
                                              DropdownMenuItem(value:v,child:Text(v))).toList(),
                                          onChanged:(v)=>setState(()=>_payFilter=v!),
                                        ))),
                                  ])),
                              filtered.isEmpty
                                  ? _EmptyState(filter:_filter, isDark:d)
                                  : ListView.separated(
                                shrinkWrap:true,
                                physics:const NeverScrollableScrollPhysics(),
                                padding:const EdgeInsets.only(bottom:12),
                                itemCount:filtered.length,
                                separatorBuilder:(_,__)=>Divider(height:1,indent:14,endIndent:14,
                                    color:_c(d,Colors.grey.shade100,_D.surface)),
                                itemBuilder:(_,i)=>_SaleCard(sale:filtered[i], isDark:d),
                              ),
                            ]))),
                  ]));
            })),
      ])),
    );
  }
}

class _GraphPoint { final String label; final double value;
const _GraphPoint({required this.label, required this.value}); }

// ─────────────────────────────────────────────────────────────
// GRAPH CARD
// ─────────────────────────────────────────────────────────────

class _GraphCard extends StatelessWidget {
  final List<_GraphPoint> points; final GraphRange range;
  final bool isDark; final ValueChanged<GraphRange> onRange;
  const _GraphCard({required this.points,required this.range,
    required this.isDark,required this.onRange});

  @override
  Widget build(BuildContext context){
    final d=isDark;
    final maxV=points.isEmpty?1.0:points.map((p)=>p.value).reduce(max);
    final safe=maxV==0?1.0:maxV;
    final avg=points.isEmpty?0.0:points.map((p)=>p.value).reduce((a,b)=>a+b)/points.length;
    final cardBg=_c(d,const Color(0xFFFDF6F1),_D.card);
    final text=_c(d,const Color(0xFF4E342E),_D.accent);
    final sub=_c(d,Colors.grey.shade500,_D.sub);

    return Column(crossAxisAlignment:CrossAxisAlignment.center,children:[
      Padding(padding:const EdgeInsets.fromLTRB(18,14,18,8),
          child:Center(child:Text('Revenue Chart',
              style:TextStyle(fontSize:15,fontWeight:FontWeight.w800,color:text)))),
      Container(
          margin:const EdgeInsets.symmetric(horizontal:18),
          padding:const EdgeInsets.all(18),
          decoration:BoxDecoration(color:cardBg, borderRadius:BorderRadius.circular(22),
              boxShadow:[BoxShadow(color:const Color(0xFF4E342E).withOpacity(d?0.2:0.05),
                  blurRadius:16,offset:const Offset(0,6))]),
          child:Column(children:[
            Row(mainAxisAlignment:MainAxisAlignment.end,children:[
              Container(
                  decoration:BoxDecoration(
                      color:_c(d,const Color(0xFFF6F6F6),_D.surface),
                      borderRadius:BorderRadius.circular(12)),
                  child:Row(mainAxisSize:MainAxisSize.min,children:GraphRange.values.map((r){
                    final active=r==range;
                    return GestureDetector(onTap:()=>onRange(r),
                        child:AnimatedContainer(duration:const Duration(milliseconds:180),
                            width:76,padding:const EdgeInsets.symmetric(vertical:6),
                            alignment:Alignment.center,
                            decoration:BoxDecoration(
                                color:active?const Color(0xFF4E342E):Colors.transparent,
                                borderRadius:BorderRadius.circular(10)),
                            child:Text(r.label, textAlign:TextAlign.center,
                                style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,
                                    color:active?Colors.white:sub))));
                  }).toList())),
            ]),
            const SizedBox(height:20),
            SizedBox(height:160,child:Row(crossAxisAlignment:CrossAxisAlignment.end,
                children:points.asMap().entries.map((e){
                  final i=e.key; final p=e.value;
                  final ratio=p.value/safe;
                  final isTop=p.value==maxV&&maxV>0;
                  return Expanded(child:Padding(
                      padding:const EdgeInsets.symmetric(horizontal:2),
                      child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
                        if(p.value>0) Padding(padding:const EdgeInsets.only(bottom:3),
                            child: FittedBox(fit: BoxFit.scaleDown,
                            child:Text(_short(p.value),textAlign:TextAlign.center,
                                style:TextStyle(fontSize:9,fontWeight:FontWeight.w700,
                                    color:isTop?const Color(0xFF4E342E):sub)))),
                        AnimatedContainer(
                            duration:Duration(milliseconds:350+i*50),curve:Curves.easeOutCubic,
                            height:max(4.0,ratio*100),
                            decoration:BoxDecoration(
                                gradient:isTop
                                    ?const LinearGradient(colors:[Color(0xFF6F4E37),Color(0xFFD4A373)],
                                    begin:Alignment.bottomCenter,end:Alignment.topCenter)
                                    :LinearGradient(colors:[
                                  const Color(0xFF4E342E).withOpacity(0.12),
                                  const Color(0xFF4E342E).withOpacity(0.28)],
                                    begin:Alignment.bottomCenter,end:Alignment.topCenter),
                                borderRadius:const BorderRadius.vertical(top:Radius.circular(6)))),
                        const SizedBox(height:6),
                        Text(p.label,textAlign:TextAlign.center,overflow:TextOverflow.clip,
                            maxLines:1,style:TextStyle(
                                fontSize:range==GraphRange.year?8:10,fontWeight:FontWeight.w600,
                                color:isTop?const Color(0xFF4E342E):const Color(0xFF6F4E37))),
                      ])));
                }).toList())),
            Container(margin:const EdgeInsets.only(top:2),height:1,
                color:_c(d,Colors.grey.shade100,_D.surface)),
            const SizedBox(height:12),
            Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              _GStat(label:'Peak',value:'₱${_short(maxV==1.0&&points.every((p)=>p.value==0)?0:maxV)}',
                  color:const Color(0xFF4E342E)),
              const SizedBox(width:20),
              _GStat(label:'Avg',value:'₱${_short(avg)}',color:const Color(0xFFD4A373)),
            ]),
          ])),
    ]);
  }
  String _short(double v)=>v>=1000?'${(v/1000).toStringAsFixed(1)}k':v.toStringAsFixed(0);
}

class _GStat extends StatelessWidget {
  final String label,value; final Color color;
  const _GStat({required this.label,required this.value,required this.color});
  @override Widget build(_)=>Row(children:[
    Container(width:8,height:8,decoration:BoxDecoration(color:color,shape:BoxShape.circle)),
    const SizedBox(width:6),
    Text('$label: ',style:TextStyle(fontSize:11,color:Colors.grey.shade500)),
    Text(value,style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:color)),
  ]);
}

// ─────────────────────────────────────────────────────────────
// TOPBAR
// ─────────────────────────────────────────────────────────────

class _Topbar extends StatelessWidget {
  final bool isDark; final VoidCallback onMenuTap;
  const _Topbar({required this.isDark,required this.onMenuTap});
  @override Widget build(_)=>Padding(padding:const EdgeInsets.symmetric(horizontal:18),
      child:SizedBox(height:56,child:Stack(alignment:Alignment.center,children:[
        Align(alignment:Alignment.centerLeft,
            child:IconButton(onPressed:onMenuTap,
                icon:Icon(Icons.menu,color:_c(isDark,const Color(0xFF2C1A0E),_D.accent)))),
        Text('Sales',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,
            fontFamily:'playwrite',color:_c(isDark,const Color(0xFF2C1A0E),_D.accent))),
      ])));
}

// ─────────────────────────────────────────────────────────────
// SUMMARY BANNER  (unchanged — always has gradient overlay)
// ─────────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final SalesFilter filter; final int totalRevenue,totalOrders,cashOrders,gcashOrders;
  const _SummaryBanner({required this.filter,required this.totalRevenue,
    required this.totalOrders,required this.cashOrders,required this.gcashOrders});
  @override Widget build(_)=>Container(
      margin:const EdgeInsets.fromLTRB(18,12,18,0),
      padding:const EdgeInsets.all(20),
      decoration:BoxDecoration(
          gradient:const LinearGradient(
              colors:[Color(0xFF2C1A0E),Color(0xFF4E342E),Color(0xFF8D6E63)],
              begin:Alignment.topLeft,end:Alignment.bottomRight),
          borderRadius:BorderRadius.circular(24),
          boxShadow:[BoxShadow(color:const Color(0xFF2C1A0E).withOpacity(0.35),
              blurRadius:20,offset:const Offset(0,8))]),
      child:Column(crossAxisAlignment:CrossAxisAlignment.center,children:[
        Row(children:[
          Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
              decoration:BoxDecoration(color:Colors.white.withOpacity(0.15),
                  borderRadius:BorderRadius.circular(20)),
              child:Text(filter.label,style:const TextStyle(fontSize:11,color:Colors.white,
                  fontWeight:FontWeight.w600))),
          const Spacer(),
          const Text('☕',style:TextStyle(fontSize:20)),
        ]),
        const SizedBox(height:12),
        const Text('Total Revenue',textAlign:TextAlign.center,
            style:TextStyle(fontSize:12,color:Colors.white60,fontWeight:FontWeight.w500)),
        const SizedBox(height:2),
        Text('₱ ${_fmt(totalRevenue)}',textAlign:TextAlign.center,
            style:const TextStyle(fontSize:34,fontWeight:FontWeight.w900,
                color:Colors.white,letterSpacing:-0.5)),
        const SizedBox(height:16),
        Row(children:[
          _StatChip(label:'Orders',value:'$totalOrders',icon:Icons.receipt_long_outlined),
          const SizedBox(width:10),
          _StatChip(label:'Cash',value:'$cashOrders',icon:Icons.payments_outlined),
          const SizedBox(width:10),
          _StatChip(label:'GCash',value:'$gcashOrders',icon:Icons.phone_android_outlined),
        ]),
      ]));
  static String _fmt(int n)=>n>=1000?'${(n/1000).toStringAsFixed(n%1000==0?0:1)}k':'$n';
}

class _StatChip extends StatelessWidget {
  final String label,value; final IconData icon;
  const _StatChip({required this.label,required this.value,required this.icon});
  @override Widget build(_)=>Expanded(child:Container(
      padding:const EdgeInsets.symmetric(vertical:10,horizontal:8),
      decoration:BoxDecoration(color:Colors.white.withOpacity(0.12),
          borderRadius:BorderRadius.circular(14),
          border:Border.all(color:Colors.white.withOpacity(0.15))),
      child:Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        Icon(icon,size:14,color:Colors.white70),const SizedBox(width:6),
        Column(crossAxisAlignment:CrossAxisAlignment.center,children:[
          Text(value,textAlign:TextAlign.center,
              style:const TextStyle(fontSize:15,fontWeight:FontWeight.w800,color:Colors.white)),
          Text(label,textAlign:TextAlign.center,
              style:const TextStyle(fontSize:9,color:Colors.white60,fontWeight:FontWeight.w500)),
        ]),
      ])));
}

// ─────────────────────────────────────────────────────────────
// FILTER TABS
// ─────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  final SalesFilter selected; final bool isDark;
  final ValueChanged<SalesFilter> onSelected;
  const _FilterTabs({required this.selected,required this.isDark,required this.onSelected});
  @override Widget build(_)=>SingleChildScrollView(
      scrollDirection:Axis.horizontal,
      padding:const EdgeInsets.fromLTRB(18,14,18,0),
      child:Row(children:SalesFilter.values.map((f){
        final active=f==selected;
        return GestureDetector(onTap:()=>onSelected(f),
            child:AnimatedContainer(duration:const Duration(milliseconds:200),
                margin:const EdgeInsets.only(right:8),
                padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
                decoration:BoxDecoration(
                    color:active?const Color(0xFF4E342E):_c(isDark,Colors.white,_D.card),
                    borderRadius:BorderRadius.circular(20),
                    boxShadow:active
                        ?[BoxShadow(color:const Color(0xFF4E342E).withOpacity(0.3),
                        blurRadius:10,offset:const Offset(0,4))]
                        :[BoxShadow(color:Colors.black.withOpacity(0.04),
                        blurRadius:6,offset:const Offset(0,2))]),
                child:Text(f.label,textAlign:TextAlign.center,
                    style:TextStyle(fontSize:13,fontWeight:FontWeight.w600,
                        color:active?Colors.white:_c(isDark,Colors.grey.shade500,_D.sub)))));
      }).toList()));
}

// ─────────────────────────────────────────────────────────────
// SALE CARD
// ─────────────────────────────────────────────────────────────

class _SaleCard extends StatefulWidget {
  final Map<String,dynamic> sale; final bool isDark;
  const _SaleCard({required this.sale,required this.isDark});
  @override State<_SaleCard> createState()=>_SaleCardState();
}
class _SaleCardState extends State<_SaleCard>{
  bool _exp=false;
  @override Widget build(_){
    final d=widget.isDark; final s=widget.sale;
    final orderId=s['orderId']??'—'; final total=s['total']??0;
    final method=(s['paymentMethod']??'cash').toString();
    final ts=s['createdAt'] as Timestamp?;
    final items=(s['items'] as List<dynamic>?)??[];
    final gcash=method=='gcash';
    final pc=gcash?const Color(0xFF0074D9):const Color(0xFF4E342E);
    final pi=gcash?Icons.phone_android_outlined:Icons.payments_outlined;
    final pl=gcash?'GCash':'Cash';
    final ds=ts!=null?_fd(ts.toDate()):'—';
    final ti=ts!=null?_ft(ts.toDate()):'';
    final text=_c(d,const Color(0xFF2C1A0E),_D.text);
    final sub=_c(d,Colors.grey.shade500,_D.sub);

    return GestureDetector(onTap:()=>setState(()=>_exp=!_exp),
        child:AnimatedContainer(duration:const Duration(milliseconds:220),
            color:Colors.transparent,
            child:Column(children:[
              Padding(padding:const EdgeInsets.all(14),child:Row(children:[
                Container(width:44,height:44,
                    decoration:BoxDecoration(color:pc.withOpacity(0.10),
                        borderRadius:BorderRadius.circular(12)),
                    child:Icon(pi,color:pc,size:20)),
                const SizedBox(width:12),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(orderId,style:TextStyle(fontSize:13,fontWeight:FontWeight.w700,color:text)),
                  const SizedBox(height:2),
                  Row(children:[
                    Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:2),
                        decoration:BoxDecoration(color:pc.withOpacity(0.10),
                            borderRadius:BorderRadius.circular(6)),
                        child:Text(pl,style:TextStyle(fontSize:10,fontWeight:FontWeight.w700,color:pc))),
                    const SizedBox(width:6),
                    Flexible(child:Text('$ds · $ti',
                        style:TextStyle(fontSize:11,color:sub),overflow:TextOverflow.ellipsis)),
                  ]),
                ])),
                Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
                  Text('₱$total',style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,color:text)),
                  Icon(_exp?Icons.keyboard_arrow_up:Icons.keyboard_arrow_down,
                      size:18,color:sub),
                ]),
              ])),
              if(_exp&&items.isNotEmpty)...[
                Divider(height:1,indent:14,endIndent:14,
                    color:_c(d,Colors.grey.shade100,_D.surface)),
                Padding(padding:const EdgeInsets.fromLTRB(14,10,14,14),child:Column(children:[
                  ...items.map((item){
                    final i=item as Map<String,dynamic>;
                    return Padding(padding:const EdgeInsets.only(bottom:6),
                        child:Row(children:[
                          Container(width:6,height:6,decoration:const BoxDecoration(
                              color:Color(0xFF8D6E63),shape:BoxShape.circle)),
                          const SizedBox(width:8),
                          Expanded(child:Text('${i['name']??'?'} x${i['qty']??1}',
                              style:TextStyle(fontSize:12,color:text,fontWeight:FontWeight.w500))),
                          Text('₱${i['subtotal']??0}',
                              style:TextStyle(fontSize:12,fontWeight:FontWeight.w700,color:sub)),
                        ]));
                  }),
                  const SizedBox(height:6),
                  Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                    Text('${items.length} item(s)',style:TextStyle(fontSize:11,color:sub)),
                    Text('Total: ₱$total',style:const TextStyle(fontSize:13,
                        fontWeight:FontWeight.w800,color:Color(0xFF4E342E))),
                  ]),
                ])),
              ],
            ])));
  }
  String _fd(DateTime d)=>'${d.year}-${_p(d.month)}-${_p(d.day)}';
  String _ft(DateTime d)=>'${_p(d.hour)}:${_p(d.minute)}';
  String _p(int n)=>n.toString().padLeft(2,'0');
}

// ─────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final SalesFilter filter; final bool isDark;
  const _EmptyState({required this.filter,required this.isDark});
  @override Widget build(_)=>Padding(padding:const EdgeInsets.symmetric(vertical:60),
      child:Column(crossAxisAlignment:CrossAxisAlignment.center,children:[
        Container(width:80,height:80,
            decoration:BoxDecoration(
                color:_c(isDark,const Color(0xFF4E342E).withOpacity(0.08),
                    _D.surface),
                shape:BoxShape.circle),
            child:const Icon(Icons.receipt_long_outlined,size:36,color:Color(0xFF8D6E63))),
        const SizedBox(height:16),
        Text('No sales yet',textAlign:TextAlign.center,
            style:TextStyle(fontSize:16,fontWeight:FontWeight.w700,
                color:_c(isDark,const Color(0xFF2C1A0E),_D.text))),
        const SizedBox(height:6),
        Text('No transactions for ${filter.label.toLowerCase()}.',textAlign:TextAlign.center,
            style:TextStyle(fontSize:13,color:_c(isDark,Colors.grey.shade500,_D.sub))),
      ]));
}