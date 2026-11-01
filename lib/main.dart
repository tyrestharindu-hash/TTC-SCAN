import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() => runApp(const TyreScanApp());

class TyreScanApp extends StatelessWidget {
  const TyreScanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'THARINDU TYRE SCAN',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
    home: const InventoryPage(),
  );
}

class TyreRecord {
  final int? id;
  final String code, serial, name, size, ownerType, ownerName, phone, notes, sidePhoto, treadPhoto, status, created;
  const TyreRecord({this.id, required this.code, required this.serial, required this.name, required this.size,
    required this.ownerType, required this.ownerName, required this.phone, required this.notes,
    required this.sidePhoto, required this.treadPhoto, required this.status, required this.created});
  Map<String,Object?> toMap() => {'id':id,'code':code,'serial':serial,'name':name,'size':size,'ownerType':ownerType,
    'ownerName':ownerName,'phone':phone,'notes':notes,'sidePhoto':sidePhoto,'treadPhoto':treadPhoto,'status':status,'created':created};
  factory TyreRecord.fromMap(Map<String,Object?> m) => TyreRecord(
    id:m['id'] as int?, code:'${m['code']??''}', serial:'${m['serial']??''}', name:'${m['name']??''}',
    size:'${m['size']??''}', ownerType:'${m['ownerType']??'Unknown'}', ownerName:'${m['ownerName']??''}',
    phone:'${m['phone']??''}', notes:'${m['notes']??''}', sidePhoto:'${m['sidePhoto']??''}',
    treadPhoto:'${m['treadPhoto']??''}', status:'${m['status']??'In stock'}', created:'${m['created']??''}');
}

class Store {
  static Database? _db;
  static Future<Database> get db async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'tharindu_tyre_scan.db');
    _db = await openDatabase(path, version: 1, onCreate: (d, v) async {
      await d.execute('''CREATE TABLE tyres(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE, serial TEXT, name TEXT, size TEXT,
      ownerType TEXT, ownerName TEXT, phone TEXT, notes TEXT, sidePhoto TEXT, treadPhoto TEXT, status TEXT, created TEXT)''');
      await d.execute('CREATE INDEX tyre_serial_idx ON tyres(serial)');
    });
    return _db!;
  }
  static Future<List<TyreRecord>> all({String search=''}) async {
    final d=await db; final s='%${search.trim()}%';
    final rows=await d.query('tyres', where:'code LIKE ? OR serial LIKE ? OR name LIKE ? OR size LIKE ? OR ownerName LIKE ? OR phone LIKE ?',
      whereArgs:[s,s,s,s,s,s], orderBy:'id DESC');
    return rows.map(TyreRecord.fromMap).toList();
  }
  static Future<void> save(TyreRecord r) async {
    final d=await db;
    if(r.id==null) {
      final n=Sqflite.firstIntValue(await d.rawQuery('SELECT COALESCE(MAX(id),0)+1 FROM tyres'))??1;
      final code='DAG-${n.toString().padLeft(5,'0')}';
      await d.insert('tyres', {...r.toMap()..remove('id'), 'code':code});
    } else { await d.update('tyres',r.toMap(),where:'id=?',whereArgs:[r.id]); }
  }
  static Future<void> delete(int id) async => (await db).delete('tyres',where:'id=?',whereArgs:[id]);
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});
  @override State<InventoryPage> createState()=>_InventoryPageState();
}
class _InventoryPageState extends State<InventoryPage> {
  final search=TextEditingController(); List<TyreRecord> records=[]; bool loading=true;
  @override void initState(){super.initState(); refresh();}
  Future<void> refresh() async { setState(()=>loading=true); records=await Store.all(search:search.text); if(mounted)setState(()=>loading=false); }
  Future<void> editor([TyreRecord? r]) async {
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>TyreEditor(record:r)));
    await refresh();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('THARINDU TYRE SCAN'),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>editor(),icon:const Icon(Icons.add),label:const Text('Add Dag tyre')),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:TextField(controller:search,onChanged:(_)=>refresh(),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search code / serial / size / owner',border:OutlineInputBorder()))),
      Expanded(child:loading?const Center(child:CircularProgressIndicator()):records.isEmpty?const Center(child:Text('No tyres saved yet')):ListView.builder(itemCount:records.length,itemBuilder:(c,i){
        final r=records[i]; return Card(child:ListTile(
          leading:const Icon(Icons.tire_repair),title:Text('${r.code} • ${r.size.isEmpty?'Size not entered':r.size}'),
          subtitle:Text('${r.name}  |  Serial: ${r.serial.isEmpty?'Not available':r.serial}\nOwner: ${r.ownerType}${r.ownerName.isEmpty?'':' • ${r.ownerName}'}  |  ${r.status}'),
          isThreeLine:true,onTap:()=>editor(r),trailing:PopupMenuButton<String>(onSelected:(v)async{
            if(v=='delete'){await Store.delete(r.id!);await refresh();}
            if(v=='edit')editor(r);
          },itemBuilder:(_)=>const [PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete'))]),
        ));
      }))
    ]));
}

class TyreEditor extends StatefulWidget {
  final TyreRecord? record; const TyreEditor({super.key,this.record});
  @override State<TyreEditor> createState()=>_TyreEditorState();
}
class _TyreEditorState extends State<TyreEditor>{
  final form=GlobalKey<FormState>(); late final TextEditingController serial,name,size,owner,phone,notes;
  String ownerType='Unknown',status='In stock',side='',tread='',ocrText=''; bool scanning=false;
  final picker=ImagePicker(); final recognizer=TextRecognizer(script:TextRecognitionScript.latin);
  @override void initState(){super.initState();final r=widget.record;
    serial=TextEditingController(text:r?.serial??'');name=TextEditingController(text:r?.name??'');size=TextEditingController(text:r?.size??'');
    owner=TextEditingController(text:r?.ownerName??'');phone=TextEditingController(text:r?.phone??'');notes=TextEditingController(text:r?.notes??'');
    ownerType=r?.ownerType??'Unknown';status=r?.status??'In stock';side=r?.sidePhoto??'';tread=r?.treadPhoto??'';
  }
  Future<void> photo(bool isSide) async {
    final x=await picker.pickImage(source:ImageSource.camera,imageQuality:85);
    if(x==null)return; setState(()=>isSide?side=x.path:tread=x.path);
    setState(()=>scanning=true);
    try {final result=await recognizer.processImage(InputImage.fromFilePath(x.path)); final txt=result.text;
      setState(()=>ocrText=txt);
      // OCR is a suggestion only: never automatically treat recognized text as confirmed tyre data.
      if(serial.text.trim().isEmpty){final lines=txt.split('\n').map((e)=>e.trim()).where((e)=>e.length>=5).toList(); if(lines.isNotEmpty) serial.text=lines.first;}
    } catch(_){setState(()=>ocrText='OCR could not read this photo. Enter details manually.');}
    if(mounted)setState(()=>scanning=false);
  }
  @override void dispose(){serial.dispose();name.dispose();size.dispose();owner.dispose();phone.dispose();notes.dispose();recognizer.close();super.dispose();}
  Widget field(String label,TextEditingController c,{bool required=false})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(controller:c,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),validator:required?(v)=>v==null||v.trim().isEmpty?'Required':null:null));
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.record==null?'Add Dag tyre':'Edit ${widget.record!.code}')),
    body:Form(key:form,child:ListView(padding:const EdgeInsets.all(16),children:[
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:()=>photo(true),icon:const Icon(Icons.camera_alt),label:const Text('Sidewall photo'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>photo(false),icon:const Icon(Icons.camera_alt),label:const Text('Tread photo')))]),
      if(side.isNotEmpty) Text('Sidewall image saved locally: ${p.basename(side)}'),
      if(tread.isNotEmpty) Text('Tread image saved locally: ${p.basename(tread)}'),
      if(scanning) const LinearProgressIndicator(),
      if(ocrText.isNotEmpty) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('OCR text (check manually):\n$ocrText')),
      field('Tyre serial number (optional)',serial),field('Tyre name / brand',name),field('Tyre size',size),
      DropdownButtonFormField<String>(value:ownerType,decoration:const InputDecoration(labelText:'Ownership',border:OutlineInputBorder()),items:const ['Customer-owned','Shop-owned','Unknown'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>ownerType=v??'Unknown')),
      const SizedBox(height:12),field('Owner name (optional)',owner),field('Owner phone (optional)',phone),
      DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Status',border:OutlineInputBorder()),items:const ['In stock','Fitted','Sold','Returned','Needs inspection'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>status=v??'In stock')),
      const SizedBox(height:12),field('Notes / tread condition',notes),
      FilledButton.icon(onPressed:()async{if(!form.currentState!.validate())return;
        final r=widget.record; final item=TyreRecord(id:r?.id,code:r?.code??'',serial:serial.text.trim(),name:name.text.trim(),size:size.text.trim(),ownerType:ownerType,ownerName:owner.text.trim(),phone:phone.text.trim(),notes:notes.text.trim(),sidePhoto:side,treadPhoto:tread,status:status,created:r?.created??DateTime.now().toIso8601String());
        await Store.save(item); if(context.mounted)Navigator.pop(context);
      },icon:const Icon(Icons.save),label:const Text('Save tyre'))
    ])));
}
