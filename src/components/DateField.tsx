import DateTimePicker from '@react-native-community/datetimepicker';
import React, { useState } from 'react';
import { Platform, StyleSheet, View } from 'react-native';
import { Button, Text } from 'react-native-paper';
import { formatDate } from '../utils/format';
import { colors } from '../utils/theme';

interface DateFieldProps {
  label: string;
  value: string; // ISO
  onChange: (iso: string) => void;
}

/**
 * Selettore data cross-platform.
 * - Su Android/iOS usa @react-native-community/datetimepicker.
 * - Su Web usa un <input type="date"> nativo (il picker RN non supporta il web).
 */
export default function DateField({ label, value, onChange }: DateFieldProps) {
  const [showPicker, setShowPicker] = useState(false);

  if (Platform.OS === 'web') {
    const isoDay = new Date(value).toISOString().slice(0, 10);
    return (
      <View style={styles.wrapper}>
        <Text variant="labelMedium" style={styles.label}>
          {label}
        </Text>
        {/* RN Web inoltra gli elementi DOM standard. */}
        {React.createElement('input', {
          type: 'date',
          value: isoDay,
          onChange: (e: { target: { value: string } }) => {
            const v = e.target.value;
            if (v) onChange(new Date(v).toISOString());
          },
          style: webInputStyle,
        })}
      </View>
    );
  }

  return (
    <View style={styles.wrapper}>
      <Text variant="labelMedium" style={styles.label}>
        {label}
      </Text>
      <Button
        mode="outlined"
        icon="calendar"
        onPress={() => setShowPicker(true)}
        style={styles.btn}
      >
        {formatDate(value)}
      </Button>
      {showPicker ? (
        <DateTimePicker
          value={new Date(value)}
          mode="date"
          display="default"
          onChange={(_event, selected?: Date) => {
            setShowPicker(false);
            if (selected) onChange(selected.toISOString());
          }}
        />
      ) : null}
    </View>
  );
}

const webInputStyle = {
  backgroundColor: colors.surfaceVariant,
  color: colors.textPrimary,
  border: `1px solid ${colors.border}`,
  borderRadius: 8,
  padding: 12,
  fontSize: 16,
} as const;

const styles = StyleSheet.create({
  wrapper: { marginBottom: 12 },
  label: { color: colors.textSecondary, marginBottom: 4 },
  btn: { borderColor: colors.border },
});
