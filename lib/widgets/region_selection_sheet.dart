import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/region_service.dart';

class RegionSelectionSheet extends StatefulWidget {
  const RegionSelectionSheet({super.key});

  @override
  State<RegionSelectionSheet> createState() => _RegionSelectionSheetState();
}

class _RegionSelectionSheetState extends State<RegionSelectionSheet> {
  List<RegionCode> _sidoList = [];
  List<RegionCode> _sigunguList = [];
  List<RegionCode> _eupmyeondongList = [];

  RegionCode? _selectedSido;
  RegionCode? _selectedSigungu;
  RegionCode? _selectedEupmyeondong;

  bool _isLoadingSido = true;
  bool _isLoadingSigungu = false;
  bool _isLoadingEupmyeondong = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadSido();
  }

  Future<void> _loadSido() async {
    final list = await RegionService.getSido();
    if (mounted) {
      setState(() {
        _sidoList = list;
        _isLoadingSido = false;
      });
    }
  }

  Future<void> _onSidoChanged(RegionCode? value) async {
    if (value == null) return;
    setState(() {
      _selectedSido = value;
      _selectedSigungu = null;
      _selectedEupmyeondong = null;
      _sigunguList = [];
      _eupmyeondongList = [];
      _isLoadingSigungu = true;
    });

    final list = await RegionService.getSigungu(value.code);
    if (mounted) {
      setState(() {
        _sigunguList = list;
        _isLoadingSigungu = false;
      });
    }
  }

  Future<void> _onSigunguChanged(RegionCode? value) async {
    if (value == null) return;
    setState(() {
      _selectedSigungu = value;
      _selectedEupmyeondong = null;
      _eupmyeondongList = [];
      _isLoadingEupmyeondong = true;
    });

    final list = await RegionService.getEupmyeondong(value.code);
    if (mounted) {
      setState(() {
        _eupmyeondongList = list;
        _isLoadingEupmyeondong = false;
      });
    }
  }

  Future<void> _submitRegion() async {
    if (_selectedEupmyeondong == null && _selectedSigungu == null && _selectedSido == null) return;
    
    setState(() {
      _isSearching = true;
    });

    // 선택된 가장 하위 지역의 전체 이름 구성
    String fullName = '';
    String shortName = '';
    if (_selectedEupmyeondong != null) {
      fullName = _selectedEupmyeondong!.name;
      shortName = fullName.split(' ').last;
    } else if (_selectedSigungu != null) {
      fullName = _selectedSigungu!.name;
      shortName = fullName.split(' ').last;
    } else if (_selectedSido != null) {
      fullName = _selectedSido!.name;
      shortName = fullName.split(' ').last;
    }

    final latLng = await RegionService.geocodeAddress(fullName);
    if (mounted) {
      setState(() {
        _isSearching = false;
      });
      if (latLng != null) {
        Navigator.pop(context, {'latLng': latLng, 'name': shortName});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('해당 지역의 좌표를 찾을 수 없습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '지역 선택',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.my_location),
                tooltip: '내 위치로 초기화',
                onPressed: () {
                  Navigator.pop(context, 'gps');
                },
              )
            ],
          ),
          const SizedBox(height: 16),
          
          // 시/도 드롭다운
          _buildDropdown(
            items: _sidoList,
            value: _selectedSido,
            hint: '시/도 선택',
            isLoading: _isLoadingSido,
            onChanged: _onSidoChanged,
            textColor: textColor,
          ),
          const SizedBox(height: 16),
          
          // 시/군/구 드롭다운
          _buildDropdown(
            items: _sigunguList,
            value: _selectedSigungu,
            hint: '시/군/구 선택',
            isLoading: _isLoadingSigungu,
            onChanged: _onSigunguChanged,
            textColor: textColor,
          ),
          const SizedBox(height: 16),

          // 읍/면/동 드롭다운
          _buildDropdown(
            items: _eupmyeondongList,
            value: _selectedEupmyeondong,
            hint: '읍/면/동 선택',
            isLoading: _isLoadingEupmyeondong,
            onChanged: (val) {
              setState(() => _selectedEupmyeondong = val);
            },
            textColor: textColor,
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: (_selectedSido == null || _isSearching) ? null : _submitRegion,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2EA043),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSearching
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('해당 지역 공원 찾기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required List<RegionCode> items,
    required RegionCode? value,
    required String hint,
    required bool isLoading,
    required ValueChanged<RegionCode?> onChanged,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: isLoading
          ? const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<RegionCode>(
                value: value,
                isExpanded: true,
                hint: Text(hint, style: TextStyle(color: textColor.withOpacity(0.5))),
                icon: Icon(Icons.arrow_drop_down, color: textColor),
                dropdownColor: Theme.of(context).cardColor,
                items: items.map((e) {
                  // 전체 이름에서 마지막 부분만 표시 (예: "서울특별시 강남구 역삼동" -> "역삼동")
                  final display = e.name.split(' ').last;
                  return DropdownMenuItem<RegionCode>(
                    value: e,
                    child: Text(display, style: TextStyle(color: textColor)),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
    );
  }
}
